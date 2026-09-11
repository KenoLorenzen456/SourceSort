import AppKit
import Observation
import SourceSortCore
import UniformTypeIdentifiers
import UserNotifications

enum SidebarSection: String, CaseIterable, Identifiable {
    case rules, activity, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .rules: "list.bullet.rectangle"
        case .activity: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

/// App state plus the sorting pipeline: FSEvents → wait until stable → match rules → act → record.
@Observable @MainActor
final class AppModel {
    static let shared = AppModel()

    var rules: [Rule] { didSet { persist(rules, "rules.json") } }
    /// Newest first.
    var activity: [ActivityEntry] { didSet { persist(activity, "activity.json") } }
    var folders: [WatchedFolder] { didSet { persist(folders, "folders.json"); restartMonitor() } }

    // Files that arrive while paused are ignored, not queued: resuming only affects new downloads.
    var isPaused = UserDefaults.standard.bool(forKey: "paused") { didSet { UserDefaults.standard.set(isPaused, forKey: "paused") } }
    var onboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone") { didSet { UserDefaults.standard.set(onboardingDone, forKey: "onboardingDone") } }
    var notificationsEnabled = UserDefaults.standard.bool(forKey: "notifications") {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notifications")
            if notificationsEnabled { requestNotificationPermission() }
        }
    }
    /// Only act on items macOS marks as downloaded (quarantine or source metadata), never on files the user made.
    var onlyDownloadedFiles = UserDefaults.standard.bool(forKey: "onlyDownloaded") { didSet { UserDefaults.standard.set(onlyDownloadedFiles, forKey: "onlyDownloaded") } }
    var stabilitySeconds = UserDefaults.standard.double(forKey: "stabilitySeconds") { didSet { UserDefaults.standard.set(stabilitySeconds, forKey: "stabilitySeconds") } }
    /// 0 keeps history forever.
    var retentionDays = UserDefaults.standard.integer(forKey: "retentionDays") {
        didSet { UserDefaults.standard.set(retentionDays, forKey: "retentionDays"); pruneHistory() }
    }

    var section: SidebarSection = .rules
    @ObservationIgnored var openWindowAction: (() -> Void)?

    @ObservationIgnored private let store = JSONStore()
    @ObservationIgnored private var monitor: FolderMonitor?
    @ObservationIgnored private var watchedPaths: Set<String> = []
    @ObservationIgnored private var inFlight: Set<String> = []
    /// Inodes already evaluated without action this session, so edits to an unmatched file don't re-log it.
    @ObservationIgnored private var evaluated: Set<UInt64> = []
    @ObservationIgnored private var pendingNotifications: [ActivityEntry] = []
    @ObservationIgnored private var notifyTask: Task<Void, Never>?

    private init() {
        UserDefaults.standard.register(defaults: ["notifications": true, "onlyDownloaded": true, "stabilitySeconds": 2.0, "retentionDays": 30])
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        rules = store.load([Rule].self, from: "rules.json") ?? []
        activity = store.load([ActivityEntry].self, from: "activity.json") ?? []
        folders = store.load([WatchedFolder].self, from: "folders.json") ?? [WatchedFolder(path: downloads.path)]
        // register(defaults:) runs after the property initializers above read UserDefaults.
        notificationsEnabled = UserDefaults.standard.bool(forKey: "notifications")
        onlyDownloadedFiles = UserDefaults.standard.bool(forKey: "onlyDownloaded")
        stabilitySeconds = UserDefaults.standard.double(forKey: "stabilitySeconds")
        retentionDays = UserDefaults.standard.integer(forKey: "retentionDays")
    }

    func start() {
        pruneHistory()
        restartMonitor()
    }

    var recent: [ActivityEntry] { Array(activity.lazy.filter { $0.outcome != .noMatch }.prefix(5)) }

    // MARK: Pipeline

    private func restartMonitor() {
        if monitor == nil {
            monitor = FolderMonitor { paths in Task { @MainActor in AppModel.shared.handle(paths) } }
        }
        watchedPaths = Set(folders.map { folder in
            // ponytail: access is started on every restart and never stopped; harmless outside the sandbox.
            var stale = false
            if let data = folder.bookmark,
               let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
            }
            // Touch the folder now so macOS asks for access at launch, not in the middle of a download.
            _ = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
            return folder.url.resolvingSymlinksInPath().path
        })
        monitor?.start(paths: Array(watchedPaths))
    }

    func handle(_ paths: [String]) {
        guard !isPaused else { return }
        let destinations = Set(rules.compactMap { $0.action.destinationURL?.resolvingSymlinksInPath().path })
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard watchedPaths.contains(url.deletingLastPathComponent().path),  // direct children only
                  !destinations.contains(path),
                  !FileStabilityService.shouldIgnore(url),
                  !inFlight.contains(path),
                  FileManager.default.fileExists(atPath: path)
            else { continue }
            inFlight.insert(path)
            let stability = FileStabilityService(stableFor: stabilitySeconds)
            Task {
                let stable = await stability.waitUntilStable(url)
                inFlight.remove(path)
                if stable { process(url) }
            }
        }
    }

    private func process(_ url: URL) {
        guard !isPaused, !FileActionService.isHandled(url), let file = try? FileMetadata.read(url) else { return }
        let fileID = FileActionService.fileID(url)
        if let fileID, evaluated.contains(fileID) { return }
        if onlyDownloadedFiles, !file.source.hasSource,
           ExtendedAttributes.get(SourceDetector.quarantineAttribute, at: url) == nil { return }

        guard let rule = RuleEngine.firstMatch(in: rules, for: file) else {
            if let fileID { evaluated.insert(fileID) }
            record(ActivityEntry(fileName: file.fileName, source: file.source, rule: nil, originalPath: url.path, outcome: .noMatch))
            return
        }
        var entry = ActivityEntry(fileName: file.fileName, source: file.source, rule: rule, originalPath: url.path, outcome: .failed)
        // Marked before acting so the file is never picked up again — even after it is moved back by Undo.
        FileActionService.markHandled(url)
        do {
            switch rule.action.kind {
            case .move:
                if let destination = rule.action.destinationURL {
                    let newURL = try FileActionService.move(url, into: destination, name: rule.action.targetName(for: file))
                    entry.newPath = newURL.path
                    entry.fileID = FileActionService.fileID(newURL)
                    entry.fileBookmark = FileActionService.bookmark(for: newURL)
                    entry.outcome = .moved
                } else {
                    entry.errorMessage = "The rule has no destination folder."
                }
            case .addTag:
                try FileActionService.addTag(rule.action.tagName, to: url)
                entry.newPath = url.path
                entry.outcome = .tagged
            case .leaveInPlace:
                entry.outcome = .leftInPlace
            }
        } catch {
            entry.errorMessage = error.localizedDescription
        }
        record(entry)
    }

    private func record(_ entry: ActivityEntry) {
        activity.insert(entry, at: 0)
        if [.moved, .tagged, .failed].contains(entry.outcome) { notify(entry) }
    }

    // MARK: Undo

    func undo(_ entry: ActivityEntry) {
        guard entry.canUndo, let newPath = entry.newPath, let index = activity.firstIndex(where: { $0.id == entry.id }) else { return }
        guard let current = FileActionService.locate(path: newPath, fileID: entry.fileID, bookmark: entry.fileBookmark) else {
            alert("“\(entry.fileName)” can’t be restored", "The file no longer exists. It may have been deleted or moved to another disk.")
            return
        }
        do {
            let original = URL(fileURLWithPath: entry.originalPath)
            let restored = try FileActionService.restore(current, to: original)
            activity[index].undoneDate = Date()
            if restored.lastPathComponent != original.lastPathComponent {
                alert("Restored as “\(restored.lastPathComponent)”",
                      "A different file named “\(original.lastPathComponent)” is already in \(original.deletingLastPathComponent().lastPathComponent), so SourceSort kept both.")
            }
        } catch {
            alert("“\(entry.fileName)” can’t be restored", error.localizedDescription)
        }
    }

    func clearHistory() { activity.removeAll() }

    private func pruneHistory() {
        guard retentionDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        if activity.contains(where: { $0.date < cutoff }) { activity.removeAll { $0.date < cutoff } }
    }

    // MARK: Folders

    func addFolder() {
        guard let url = chooseFolder(message: "Choose a folder for SourceSort to watch.") else { return }
        guard !folders.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return }
        folders.append(WatchedFolder(path: url.path, bookmark: Self.folderBookmark(url)))
    }

    func replaceFolders(with url: URL) {
        folders = [WatchedFolder(path: url.path, bookmark: Self.folderBookmark(url))]
    }

    static func folderBookmark(_ url: URL) -> Data? {
        (try? url.bookmarkData(options: .withSecurityScope)) ?? (try? url.bookmarkData())
    }

    func chooseFolder(message: String, startingAt path: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = message
        if let path { panel.directoryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: Windows, alerts, notifications

    func showMainWindow(_ section: SidebarSection? = nil) {
        if let section { self.section = section }
        NSApp.setActivationPolicy(.regular)
        openWindowAction?()
        NSApp.activate()
    }

    func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }  // UNUserNotificationCenter needs an app bundle
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Batches notifications: several downloads finishing together produce one summary.
    private func notify(_ entry: ActivityEntry) {
        guard notificationsEnabled, Bundle.main.bundleIdentifier != nil else { return }
        pendingNotifications.append(entry)
        notifyTask?.cancel()
        notifyTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let batch = pendingNotifications
            pendingNotifications = []
            let failed = batch.filter { $0.outcome == .failed }.count
            let content = UNMutableNotificationContent()
            content.threadIdentifier = "sorting"
            if batch.count == 1, let e = batch.first {
                content.title = e.outcome == .failed ? "Couldn’t sort “\(e.fileName)”" : e.fileName
                content.body = e.resultText
            } else if failed == 0 {
                content.title = "Sorted \(batch.count) downloads"
                content.body = batch.map(\.fileName).joined(separator: ", ")
            } else {
                content.title = "Sorted \(batch.count - failed) of \(batch.count) downloads"
                content.body = "\(failed) couldn’t be sorted. Open Activity for details."
            }
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    private func persist<T: Encodable>(_ value: T, _ name: String) {
        do { try store.save(value, to: name) } catch { NSLog("SourceSort: could not save \(name): \(error)") }
    }
}

extension ActivityEntry {
    var resultText: String {
        if undoneDate != nil { return "Undone" }
        switch outcome {
        case .moved: return "Moved to \(URL(fileURLWithPath: newPath ?? "/").deletingLastPathComponent().lastPathComponent)"
        case .tagged: return "Tagged"
        case .leftInPlace: return "Left in place"
        case .noMatch: return "No matching rule"
        case .failed: return errorMessage ?? "Failed"
        }
    }

    var icon: NSImage {
        let path = undoneDate == nil ? (newPath ?? originalPath) : originalPath
        if FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: (fileName as NSString).pathExtension) ?? .data)
    }

    func revealInFinder() {
        let path = undoneDate == nil ? (newPath ?? originalPath) : originalPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

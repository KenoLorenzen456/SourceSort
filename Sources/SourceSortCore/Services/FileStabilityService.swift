import Foundation

/// Decides when a download is finished and safe to move.
public struct FileStabilityService: Sendable {
    /// In-progress download extensions (Chrome, Safari, Firefox, Opera, generic).
    public static let temporaryExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload", "downloading", "tmp"]

    public var interval: Duration
    public var requiredStableChecks: Int
    public var timeout: Duration

    /// `stableFor`: how long size and modification date must stay unchanged.
    public init(stableFor seconds: Double = 2, interval: Double = 1, timeout: Double = 6 * 3600) {
        self.interval = .milliseconds(Int(interval * 1000))
        self.requiredStableChecks = max(1, Int((seconds / interval).rounded()))
        self.timeout = .seconds(timeout)
    }

    /// Hidden files and in-progress downloads are never processed; the finished file arrives under its real name.
    public static func shouldIgnore(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") || name.hasPrefix("Unconfirmed ")  // Chrome's pre-rename placeholder
            || temporaryExtensions.contains(url.pathExtension.lowercased())
    }

    /// Waits until the item stops changing. Returns `false` if it disappears, the task is cancelled, or it times out.
    public func waitUntilStable(_ url: URL) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var last: Snapshot?
        var stableChecks = 0
        while clock.now < deadline {
            guard let snap = Self.snapshot(url) else { return false }
            stableChecks = (snap == last && !Self.hasInProgressSibling(url)) ? stableChecks + 1 : 0
            last = snap
            // Firefox creates an empty placeholder next to "name.part"; empty files get extra time.
            let needed = snap.size == 0 ? requiredStableChecks * 3 : requiredStableChecks
            if stableChecks >= needed { return true }
            do { try await Task.sleep(for: interval) } catch { return false }
        }
        return false
    }

    struct Snapshot: Equatable {
        var size: Int64
        var modified: Date
        var count: Int
    }

    /// For folders (e.g. archives Safari auto-extracts) the snapshot covers their whole contents.
    static func snapshot(_ url: URL) -> Snapshot? {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        var snap = Snapshot(size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate ?? .distantPast, count: 1)
        if v.isDirectory == true, let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let item as URL in items {
                guard let iv = try? item.resourceValues(forKeys: Set(keys)) else { continue }
                snap.size += Int64(iv.fileSize ?? 0)
                snap.modified = max(snap.modified, iv.contentModificationDate ?? .distantPast)
                snap.count += 1
            }
        }
        return snap
    }

    static func hasInProgressSibling(_ url: URL) -> Bool {
        ["part", "crdownload", "download"].contains { FileManager.default.fileExists(atPath: url.path + "." + $0) }
    }
}

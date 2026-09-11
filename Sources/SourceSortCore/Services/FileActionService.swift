import Foundation

public enum FileActionError: LocalizedError, Equatable {
    case fileMissing(String)
    case volumeUnavailable(String)
    case notAFolder(String)
    case cannotCreateFolder(String, String)
    case moveFailed(String)
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .fileMissing(let p): "The file no longer exists at \(Self.tilde(p))."
        case .volumeUnavailable(let v): "The disk “\(v)” is not available."
        case .notAFolder(let p): "\(Self.tilde(p)) is not a folder."
        case .cannotCreateFolder(let p, let why): "Could not create \(Self.tilde(p)): \(why)"
        case .moveFailed(let why): "The file could not be moved: \(why)"
        case .verificationFailed: "The move could not be verified. The original file was left in place."
        }
    }

    static func tilde(_ p: String) -> String { (p as NSString).abbreviatingWithTildeInPath }
}

/// All file-system mutations. Never replaces or deletes an existing item: name collisions get " 2", " 3", …
public enum FileActionService {
    static let handledAttribute = "com.sourcesort.handled"

    /// Moves `source` into `directory` (created if needed). Returns the final location.
    @discardableResult
    public static func move(_ source: URL, into directory: URL, name: String? = nil) throws -> URL {
        guard exists(source) else { throw FileActionError.fileMissing(source.path) }
        try ensureDirectory(directory)
        let name = name ?? source.lastPathComponent
        if directory.standardizedFileURL.path == source.deletingLastPathComponent().standardizedFileURL.path,
           name == source.lastPathComponent {
            return source  // already where the rule wants it
        }
        return try transfer(source, into: directory, name: name)
    }

    /// Moves a sorted file back to `originalURL`. If that name is taken, uses "name 2" instead of overwriting.
    /// Recreates the original folder if it was deleted.
    @discardableResult
    public static func restore(_ current: URL, to originalURL: URL) throws -> URL {
        guard exists(current) else { throw FileActionError.fileMissing(current.path) }
        let directory = originalURL.deletingLastPathComponent()
        try ensureDirectory(directory)
        return try transfer(current, into: directory, name: originalURL.lastPathComponent)
    }

    public static func addTag(_ tag: String, to url: URL) throws {
        let tag = tag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        var tags = try url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        guard !tags.contains(tag) else { return }
        tags.append(tag)
        try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    // MARK: Undo support

    /// Finds a previously sorted file: at its recorded path, or wherever it went since (via bookmark).
    /// `fileID` guards against restoring a different file that later took the same path.
    public static func locate(path: String, fileID: UInt64?, bookmark: Data?) -> URL? {
        func isSame(_ url: URL) -> Bool { exists(url) && (fileID == nil || self.fileID(url) == fileID) }
        let url = URL(fileURLWithPath: path)
        if isSame(url) { return url }
        var stale = false
        if let bookmark,
           let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale),
           isSame(resolved) {
            return resolved
        }
        // Bookmarks resolve by path first, so a new file at the old path hides the moved one.
        // Fall back to looking the inode up directly on that volume.
        if let fileID, let found = pathForInode(fileID, near: path), isSame(found) { return found }
        return nil
    }

    /// Current path of inode `ino` on the volume holding `path` (via the /.vol file system), or nil.
    static func pathForInode(_ ino: UInt64, near path: String) -> URL? {
        var dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        var st = stat()
        while stat(dir.path, &st) != 0 {
            guard dir.path != "/" else { return nil }
            dir.deleteLastPathComponent()
        }
        let fd = open("/.vol/\(st.st_dev)/\(ino)", O_EVTONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &buffer) == 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer))
    }

    public static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public static func fileID(_ url: URL) -> UInt64? {
        var st = stat()
        return lstat(url.path, &st) == 0 ? UInt64(st.st_ino) : nil
    }

    // MARK: Handled marker — keeps SourceSort from re-sorting files it already acted on (including undone ones).

    public static func markHandled(_ url: URL) { ExtendedAttributes.set(handledAttribute, Data("1".utf8), at: url) }
    public static func isHandled(_ url: URL) -> Bool { ExtendedAttributes.get(handledAttribute, at: url) != nil }

    // MARK: Names

    /// "invoice.pdf" → "invoice 2.pdf" → "invoice 3.pdf" … returns the first name not present in `directory`.
    public static func uniqueURL(for name: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(name)
        let (base, ext) = splitName(name)
        var n = 2
        while exists(candidate) {
            candidate = directory.appendingPathComponent("\(base) \(n)\(ext)")
            n += 1
        }
        return candidate
    }

    /// Splits "archive.tar.gz" → ("archive", ".tar.gz"), "invoice.pdf" → ("invoice", ".pdf"), ".env" → (".env", "").
    public static func splitName(_ name: String) -> (base: String, ext: String) {
        let lower = name.lowercased()
        for compound in [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst"] where lower.hasSuffix(compound) && lower.count > compound.count {
            let i = name.index(name.endIndex, offsetBy: -compound.count)
            return (String(name[..<i]), String(name[i...]))
        }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[dot...]))
    }

    /// `lstat`-based: also sees broken symlinks, which `FileManager.fileExists` misses.
    static func exists(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0
    }

    // MARK: Moving

    static func ensureDirectory(_ directory: URL) throws {
        let parts = directory.standardizedFileURL.pathComponents  // ["/", "Volumes", "Disk", …]
        if parts.count >= 3, parts[1] == "Volumes", !exists(URL(fileURLWithPath: "/Volumes/" + parts[2])) {
            throw FileActionError.volumeUnavailable(parts[2])
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir) {
            if !isDir.boolValue { throw FileActionError.notAFolder(directory.path) }
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw FileActionError.cannotCreateFolder(directory.path, error.localizedDescription)
        }
    }

    static func transfer(_ source: URL, into directory: URL, name: String) throws -> URL {
        for _ in 0..<1000 {
            let target = uniqueURL(for: name, in: directory)
            // RENAME_EXCL: atomic, and fails instead of replacing if `target` appeared in the meantime.
            let err: Int32 = source.withUnsafeFileSystemRepresentation { s in
                target.withUnsafeFileSystemRepresentation { t in
                    renamex_np(s!, t!, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
                }
            }
            switch err {
            case 0:
                guard exists(target), !exists(source) else { throw FileActionError.verificationFailed }
                return target
            case EEXIST: continue  // lost a race for this name; take the next one
            case EXDEV: return try copyAcrossVolumes(source, to: target)
            default: throw FileActionError.moveFailed(String(cString: strerror(err)))
            }
        }
        throw FileActionError.moveFailed("no free file name")
    }

    /// Different volume: copy, verify, then remove the original. On any failure the original stays untouched.
    static func copyAcrossVolumes(_ source: URL, to target: URL) throws -> URL {
        let fm = FileManager.default
        do {
            try fm.copyItem(at: source, to: target)  // fails rather than overwrites if target exists
        } catch {
            if (error as NSError).code != NSFileWriteFileExistsError { try? fm.removeItem(at: target) }  // our partial copy
            throw FileActionError.moveFailed(error.localizedDescription)
        }
        guard totalSize(target) == totalSize(source) else {
            try? fm.removeItem(at: target)
            throw FileActionError.verificationFailed
        }
        do {
            try fm.removeItem(at: source)
        } catch {
            try? fm.removeItem(at: target)
            throw FileActionError.moveFailed("could not remove the original: \(error.localizedDescription)")
        }
        return target
    }

    static func totalSize(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        guard (try? url.resourceValues(forKeys: keys).isDirectory) == true else {
            return Int64((try? url.resourceValues(forKeys: keys).fileSize) ?? 0)
        }
        let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        return items?.reduce(Int64(0)) { sum, item in
            sum + Int64(((item as? URL).flatMap { try? $0.resourceValues(forKeys: keys).fileSize }) ?? 0)
        } ?? 0
    }
}

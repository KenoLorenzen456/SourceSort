import CoreServices
import Foundation

/// Reads download-origin metadata that browsers attach to files.
///
/// Sources, in order:
/// 1. `com.apple.metadata:kMDItemWhereFroms` extended attribute — `[downloadURL, referrerURL]`,
///    written by Safari, Chrome, Firefox, Mail, AirDrop. Read directly so it works before Spotlight indexes the file.
/// 2. Spotlight's `kMDItemWhereFroms` (same data, via the metadata store) as a fallback.
/// 3. `com.apple.quarantine` — `flags;hex-time;agent;uuid`, gives the originating application.
public enum SourceDetector {
    public static let whereFromsAttribute = "com.apple.metadata:kMDItemWhereFroms"
    public static let quarantineAttribute = "com.apple.quarantine"

    public static func detect(at url: URL) -> DetectedSource {
        let froms = whereFroms(at: url).compactMap(parseURL)
        return DetectedSource(
            originalURL: froms.first,
            referrerURL: froms.count > 1 ? froms[1] : nil,
            originatingApplication: originatingApplication(at: url)
        )
    }

    public static func whereFroms(at url: URL) -> [String] {
        if let data = ExtendedAttributes.get(whereFromsAttribute, at: url),
           let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String],
           !list.isEmpty {
            return list
        }
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let list = MDItemCopyAttribute(item, kMDItemWhereFroms) as? [String] {
            return list
        }
        return []
    }

    public static func originatingApplication(at url: URL) -> String? {
        guard let data = ExtendedAttributes.get(quarantineAttribute, at: url),
              let value = String(data: data, encoding: .utf8) else { return nil }
        let parts = value.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count > 2 else { return nil }
        let agent = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        switch agent {
        case "": return nil
        case "sharingd": return "AirDrop"
        default: return agent
        }
    }

    /// Normalized host for a URL string: lowercased, no `www.`, no port. `nil` for invalid or host-less URLs.
    ///
    ///     "https://www.GitHub.com:443/foo?x=1" → "github.com"
    ///     "blob:https://discord.com/abc"       → "discord.com"
    public static func domain(from string: String) -> String? {
        guard let url = parseURL(string), var host = url.host?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }

    static func parseURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("blob:") { s.removeFirst(5) }  // Chrome/Firefox blob downloads
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if let url = URL(string: s), url.host != nil { return url }
        if !s.contains("://"), let url = URL(string: "https://" + s), url.host != nil { return url }  // "github.com/foo"
        return nil
    }
}

public enum ExtendedAttributes {
    public static func get(_ name: String, at url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
            return read > 0 ? data.prefix(read) : nil
        }
    }

    @discardableResult
    public static func set(_ name: String, _ data: Data, at url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return data.withUnsafeBytes { setxattr(path, name, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) } == 0
        }
    }
}

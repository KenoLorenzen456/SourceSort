import Foundation

/// Where a downloaded file came from, as recorded by macOS / the browser.
public struct DetectedSource: Codable, Hashable, Sendable {
    /// The URL the file's bytes were downloaded from (first `kMDItemWhereFroms` entry).
    public var originalURL: URL?
    /// The page that linked to the download (second `kMDItemWhereFroms` entry), if recorded.
    public var referrerURL: URL?
    /// The website shown to the user: the referring page's host if known, else the download host.
    /// e.g. a GitHub release is served from `release-assets.githubusercontent.com` but the referrer is `github.com`.
    public var domain: String?
    /// Every host found in the metadata. "Source domain" conditions match against any of them.
    public var domains: [String]
    /// The app that downloaded the file (from the quarantine attribute), e.g. "Safari".
    public var originatingApplication: String?

    public init(originalURL: URL? = nil, referrerURL: URL? = nil, originatingApplication: String? = nil) {
        self.originalURL = originalURL
        self.referrerURL = referrerURL
        self.originatingApplication = originatingApplication
        let hosts = [referrerURL, originalURL].compactMap { $0.flatMap { SourceDetector.domain(from: $0.absoluteString) } }
        var unique: [String] = []
        for h in hosts where !unique.contains(h) { unique.append(h) }
        self.domains = unique
        self.domain = unique.first
    }

    public static let none = DetectedSource()

    public var hasSource: Bool { domain != nil }
}

import Foundation

public struct ActivityEntry: Identifiable, Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case moved, tagged, leftInPlace, noMatch, failed
    }

    public var id = UUID()
    public var date = Date()
    public var fileName: String
    public var sourceDomain: String?
    public var sourceURL: String?
    public var ruleID: UUID?
    public var ruleName: String?
    public var originalPath: String
    public var newPath: String?
    public var outcome: Outcome
    public var errorMessage: String?

    // Undo: the file's inode and a bookmark let Undo find it even if it was moved again.
    public var fileID: UInt64?
    public var fileBookmark: Data?
    public var undoneDate: Date?

    public init(fileName: String, source: DetectedSource, rule: Rule?, originalPath: String, outcome: Outcome) {
        self.fileName = fileName
        self.sourceDomain = source.domain
        self.sourceURL = (source.referrerURL ?? source.originalURL)?.absoluteString
        self.ruleID = rule?.id
        self.ruleName = rule?.name
        self.originalPath = originalPath
        self.outcome = outcome
    }

    public var canUndo: Bool { outcome == .moved && undoneDate == nil && newPath != nil }
}

public struct WatchedFolder: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var path: String
    /// Security-scoped bookmark from the Open panel; keeps access across launches (and under App Sandbox later).
    public var bookmark: Data?

    public init(path: String, bookmark: Data? = nil) {
        self.path = path
        self.bookmark = bookmark
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    public var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

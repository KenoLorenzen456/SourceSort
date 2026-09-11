import Foundation

public enum ConditionMode: String, Codable, CaseIterable, Sendable {
    case all, any
}

public struct RuleAction: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case move, addTag, leaveInPlace

        public var title: String {
            switch self {
            case .move: "Move File"
            case .addTag: "Add Finder Tag"
            case .leaveInPlace: "Leave in Place"
            }
        }
    }

    public var kind: Kind
    /// Destination folder for `.move`; may start with "~".
    public var destinationPath: String = ""
    /// Tag for `.addTag`.
    public var tagName: String = ""
    /// Optional new name for `.move`, without extension. Tokens: {name} {domain} {date}. Empty keeps the name.
    public var renameTemplate: String = ""

    public init(kind: Kind, destinationPath: String = "", tagName: String = "", renameTemplate: String = "") {
        self.kind = kind
        self.destinationPath = destinationPath
        self.tagName = tagName
        self.renameTemplate = renameTemplate
    }

    public static func move(to path: String) -> RuleAction { RuleAction(kind: .move, destinationPath: path) }

    public var destinationURL: URL? {
        let path = destinationPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
    }

    /// The file name to use after renaming, or `nil` to keep the original.
    public func targetName(for file: FileMetadata, date: Date = Date()) -> String? {
        let template = renameTemplate.trimmingCharacters(in: .whitespaces)
        guard kind == .move, !template.isEmpty else { return nil }
        let (base, ext) = FileActionService.splitName(file.fileName)
        let day = date.formatted(.iso8601.year().month().day())
        var name = template
            .replacingOccurrences(of: "{name}", with: base)
            .replacingOccurrences(of: "{domain}", with: file.source.domain ?? "unknown")
            .replacingOccurrences(of: "{date}", with: day)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name.hasPrefix(".") { name = base }
        return name + ext
    }

    public var summary: String {
        switch kind {
        case .move: destinationPath.isEmpty ? "Move" : destinationPath
        case .addTag: "Tag “\(tagName)”"
        case .leaveInPlace: "Leave in place"
        }
    }
}

/// A sorting rule. A rule's priority is its position in the rules list: the first enabled matching rule wins.
public struct Rule: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var isEnabled = true
    public var conditions: [RuleCondition]
    public var conditionMode: ConditionMode = .all
    public var action: RuleAction

    public init(name: String, isEnabled: Bool = true, conditions: [RuleCondition], conditionMode: ConditionMode = .all, action: RuleAction) {
        self.name = name
        self.isEnabled = isEnabled
        self.conditions = conditions
        self.conditionMode = conditionMode
        self.action = action
    }

    public var conditionSummary: String {
        conditions.map(\.summary).joined(separator: conditionMode == .all ? " + " : " or ")
    }
}

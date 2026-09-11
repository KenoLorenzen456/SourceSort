import Foundation

/// Pure rule evaluation — no UI, no file system access. All comparisons are case-insensitive.
public enum RuleEngine {
    /// Rules run top to bottom; the first enabled rule that matches wins.
    public static func firstMatch(in rules: [Rule], for file: FileMetadata) -> Rule? {
        rules.first { $0.isEnabled && matches($0, file) }
    }

    public static func matches(_ rule: Rule, _ file: FileMetadata) -> Bool {
        guard !rule.conditions.isEmpty else { return false }  // an empty rule must never sort everything
        switch rule.conditionMode {
        case .all: return rule.conditions.allSatisfy { matches($0, file) }
        case .any: return rule.conditions.contains { matches($0, file) }
        }
    }

    public static func matches(_ c: RuleCondition, _ file: FileMetadata) -> Bool {
        let values = c.values
        switch c.field {
        case .sourceDomain:
            // "is github.com" also matches www.github.com and subdomains like codeload.github.com.
            let wanted = c.op == .is ? values.map { SourceDetector.domain(from: $0) ?? $0 } : values
            return file.source.domains.contains { domain in
                wanted.contains { w in c.op == .contains ? domain.contains(w) : (domain == w || domain.hasSuffix("." + w)) }
            }
        case .sourceURL:
            let urls = [file.source.originalURL, file.source.referrerURL].compactMap { $0?.absoluteString.lowercased() }
            return urls.contains { url in values.contains { url.contains($0) } }
        case .originatingApplication:
            guard let app = file.source.originatingApplication?.lowercased() else { return false }
            return text(app, c.op, values)
        case .fileName:
            return text(file.fileName.lowercased(), c.op, values)
        case .fileExtension:
            return values.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.contains(file.fileExtension)
        case .fileType:
            return FileKind(rawValue: c.value)?.matches(file) ?? false
        case .fileSize:
            guard !file.isDirectory,
                  let mb = Double(c.value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) else { return false }
            let bytes = mb * 1_000_000  // Finder uses decimal megabytes
            return c.op == .greaterThan ? Double(file.size) > bytes : Double(file.size) < bytes
        }
    }

    private static func text(_ s: String, _ op: ConditionOperator, _ values: [String]) -> Bool {
        values.contains { v in
            switch op {
            case .is: s == v
            case .contains: s.contains(v)
            case .startsWith: s.hasPrefix(v)
            case .endsWith: s.hasSuffix(v)
            case .greaterThan, .lessThan: false
            }
        }
    }
}

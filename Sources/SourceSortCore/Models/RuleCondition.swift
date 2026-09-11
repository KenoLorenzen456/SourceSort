import Foundation
import UniformTypeIdentifiers

public enum ConditionField: String, Codable, CaseIterable, Identifiable, Sendable {
    case sourceDomain, sourceURL, originatingApplication
    case fileName, fileExtension, fileType, fileSize

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sourceDomain: "Source domain"
        case .sourceURL: "Source URL"
        case .originatingApplication: "Downloaded by"
        case .fileName: "Filename"
        case .fileExtension: "Extension"
        case .fileType: "File type"
        case .fileSize: "File size"
        }
    }

    public var operators: [ConditionOperator] {
        switch self {
        case .sourceDomain: [.is, .contains]
        case .sourceURL: [.contains]
        case .originatingApplication: [.is, .contains]
        case .fileName: [.is, .contains, .startsWith, .endsWith]
        case .fileExtension, .fileType: [.is]
        case .fileSize: [.greaterThan, .lessThan]
        }
    }

    public var placeholder: String {
        switch self {
        case .sourceDomain: "github.com"
        case .sourceURL: "/releases/"
        case .originatingApplication: "Safari"
        case .fileName: "invoice"
        case .fileExtension: "pdf"
        case .fileType: ""
        case .fileSize: "MB"
        }
    }

    public var isSourceField: Bool { [.sourceDomain, .sourceURL, .originatingApplication].contains(self) }
}

public enum ConditionOperator: String, Codable, CaseIterable, Sendable {
    case `is`, contains, startsWith, endsWith, greaterThan, lessThan

    public var title: String {
        switch self {
        case .is: "is"
        case .contains: "contains"
        case .startsWith: "starts with"
        case .endsWith: "ends with"
        case .greaterThan: "is greater than"
        case .lessThan: "is less than"
        }
    }
}

/// Broad file categories for the "File type is" condition.
public enum FileKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case image, video, audio, pdf, document, archive, diskImage, installer, folder

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .audio: "Audio"
        case .pdf: "PDF"
        case .document: "Document"
        case .archive: "Archive"
        case .diskImage: "Disk Image"
        case .installer: "Installer"
        case .folder: "Folder"
        }
    }

    private var types: [UTType] {
        switch self {
        case .image: [.image]
        case .video: [.movie]
        case .audio: [.audio]
        case .pdf: [.pdf]
        case .document: [.text, .compositeContent, .spreadsheet, .presentation]
        case .archive: [.archive]
        case .diskImage: [.diskImage]
        case .installer, .folder: []
        }
    }

    // Extensions Launch Services may not know on a clean system.
    private var extensions: Set<String> {
        switch self {
        case .document: ["doc", "docx", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key", "odt", "ods", "odp", "rtf", "txt", "md", "csv", "epub"]
        case .archive: ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst"]
        case .diskImage: ["dmg", "iso", "img"]
        case .installer: ["pkg", "mpkg", "exe", "msi", "deb", "rpm", "apk"]
        default: []
        }
    }

    public func matches(_ file: FileMetadata) -> Bool {
        if self == .folder { return file.isDirectory }
        if file.isDirectory { return false }
        if extensions.contains(file.fileExtension) { return true }
        guard let type = file.contentType else { return false }
        return types.contains { type.conforms(to: $0) }
    }
}

public struct RuleCondition: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var field: ConditionField
    public var op: ConditionOperator
    public var value: String

    public init(_ field: ConditionField, _ op: ConditionOperator, _ value: String) {
        self.field = field
        self.op = op
        self.value = value
    }

    /// Comma-separated alternatives ("gguf, safetensors"), lowercased and trimmed. Any may match.
    public var values: [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// Short human summary, e.g. "huggingface.co", ".gguf, .safetensors", "> 100 MB".
    public var summary: String {
        switch field {
        case .sourceDomain: op == .is ? values.joined(separator: ", ") : "domain contains “\(value)”"
        case .sourceURL: "URL contains “\(value)”"
        case .originatingApplication: "from \(value)"
        case .fileName: "name \(op.title) “\(value)”"
        case .fileExtension: values.map { "." + $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.joined(separator: ", ")
        case .fileType: FileKind(rawValue: value)?.title ?? value
        case .fileSize: "\(op == .greaterThan ? ">" : "<") \(value) MB"
        }
    }
}

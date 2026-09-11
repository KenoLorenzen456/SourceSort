import Foundation
import UniformTypeIdentifiers

/// Everything the rule engine looks at for one file.
public struct FileMetadata: Sendable {
    public var url: URL
    public var isDirectory: Bool
    public var size: Int64
    public var contentType: UTType?
    public var source: DetectedSource

    public var fileName: String { url.lastPathComponent }
    public var fileExtension: String { url.pathExtension.lowercased() }

    public init(url: URL, isDirectory: Bool = false, size: Int64 = 0, contentType: UTType? = nil, source: DetectedSource = .none) {
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.contentType = contentType ?? UTType(filenameExtension: url.pathExtension)
        self.source = source
    }

    public static func read(_ url: URL) throws -> FileMetadata {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentTypeKey])
        // ponytail: folders report size 0; sum contents if "File size" rules on folders are ever needed.
        return FileMetadata(
            url: url,
            isDirectory: values.isDirectory ?? false,
            size: Int64(values.fileSize ?? 0),
            contentType: values.contentType,
            source: SourceDetector.detect(at: url)
        )
    }
}

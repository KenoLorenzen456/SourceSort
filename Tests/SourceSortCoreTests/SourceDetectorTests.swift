import Foundation
import Testing
@testable import SourceSortCore

@Suite struct SourceDetectorTests {
    @Test(arguments: [
        ("https://github.com/foo", "github.com"),
        ("https://huggingface.co/Qwen/model", "huggingface.co"),
        ("https://www.amazon.de/gp/css/order", "amazon.de"),
        ("https://WWW.GitHub.COM/foo", "github.com"),
        ("https://cdn-lfs.huggingface.co/repos/x", "cdn-lfs.huggingface.co"),
        ("https://example.com/file.zip?token=abc&x=1#frag", "example.com"),
        ("http://localhost:8080/file", "localhost"),
        ("https://example.com:8443/a", "example.com"),
        ("blob:https://discord.com/1234-5678", "discord.com"),
        ("github.com/foo/bar", "github.com"),
        ("https://example.com./x", "example.com"),
    ])
    func domainParsing(input: String, expected: String) {
        #expect(SourceDetector.domain(from: input) == expected)
    }

    @Test(arguments: ["", "not a url", "file:///Users/me/file.zip", "data:text/plain;base64,SGVsbG8=", "https://"])
    func invalidURLsHaveNoDomain(input: String) {
        #expect(SourceDetector.domain(from: input) == nil)
    }

    @Test func referrerDomainIsPrimary() {
        let s = DetectedSource(
            originalURL: URL(string: "https://release-assets.githubusercontent.com/x.zip"),
            referrerURL: URL(string: "https://github.com/owner/repo/releases")
        )
        #expect(s.domain == "github.com")
        #expect(s.domains == ["github.com", "release-assets.githubusercontent.com"])
    }

    /// Writes the same metadata a browser writes and reads it back from disk.
    @Test func readsBrowserMetadataFromFile() throws {
        let url = try TempDir().file("model.gguf")
        let froms = ["https://cdn-lfs.huggingface.co/repos/abc/model.gguf", "https://huggingface.co/Qwen/Qwen3"]
        let plist = try PropertyListSerialization.data(fromPropertyList: froms, format: .binary, options: 0)
        #expect(ExtendedAttributes.set(SourceDetector.whereFromsAttribute, plist, at: url))
        #expect(ExtendedAttributes.set(SourceDetector.quarantineAttribute, Data("0083;66e1b2c3;Safari;ABC-123".utf8), at: url))

        let s = SourceDetector.detect(at: url)
        #expect(s.originalURL?.absoluteString == froms[0])
        #expect(s.referrerURL?.absoluteString == froms[1])
        #expect(s.domain == "huggingface.co")
        #expect(s.originatingApplication == "Safari")
    }

    @Test func fileWithoutMetadata() throws {
        let url = try TempDir().file("photo.jpg")
        let s = SourceDetector.detect(at: url)
        #expect(s.domain == nil && s.originalURL == nil && s.originatingApplication == nil)
    }
}

/// A fresh temporary directory per test.
struct TempDir {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("SourceSortTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    @discardableResult
    func file(_ name: String, contents: String = "data", in sub: String? = nil) throws -> URL {
        var dir = url
        if let sub { dir = url.appendingPathComponent(sub); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        let f = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: f)
        return f
    }
}

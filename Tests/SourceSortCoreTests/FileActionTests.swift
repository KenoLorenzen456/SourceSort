import Foundation
import Testing
@testable import SourceSortCore

struct FileActionTests {
    let tmp: TempDir
    init() throws { tmp = try TempDir() }

    func path(_ p: String) -> URL { tmp.url.appendingPathComponent(p) }
    func contents(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    @Test func splitNames() {
        #expect(FileActionService.splitName("invoice.pdf") == ("invoice", ".pdf"))
        #expect(FileActionService.splitName("archive.tar.gz") == ("archive", ".tar.gz"))
        #expect(FileActionService.splitName("README") == ("README", ""))
        #expect(FileActionService.splitName(".env") == (".env", ""))
        #expect(FileActionService.splitName("my.report.v2.docx") == ("my.report.v2", ".docx"))
    }

    @Test func collisionNamesNeverOverwrite() throws {
        try tmp.file("invoice.pdf", contents: "existing", in: "dest")
        try tmp.file("invoice 2.pdf", contents: "existing 2", in: "dest")
        let a = try tmp.file("invoice.pdf", contents: "new", in: "dl")

        let moved = try FileActionService.move(a, into: path("dest"))
        #expect(moved.lastPathComponent == "invoice 3.pdf")
        #expect(contents(moved) == "new")
        #expect(contents(path("dest/invoice.pdf")) == "existing")
        #expect(contents(path("dest/invoice 2.pdf")) == "existing 2")
        #expect(!FileManager.default.fileExists(atPath: a.path))

        try tmp.file("x.tar.gz", in: "dest")
        let b = try tmp.file("x.tar.gz", contents: "b", in: "dl")
        #expect(try FileActionService.move(b, into: path("dest")).lastPathComponent == "x 2.tar.gz")
    }

    @Test func moveCreatesDestinationAndRenames() throws {
        let f = try tmp.file("a.zip", in: "dl")
        let moved = try FileActionService.move(f, into: path("new/nested"), name: "b.zip")
        #expect(moved.path == path("new/nested/b.zip").path)
        #expect(FileManager.default.fileExists(atPath: moved.path))
    }

    @Test func moveFolder() throws {
        try tmp.file("README", in: "dl/Repo")
        let moved = try FileActionService.move(path("dl/Repo"), into: path("dest"))
        #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("README").path))
    }

    @Test func moveErrors() throws {
        #expect(throws: FileActionError.fileMissing(path("nope").path)) {
            try FileActionService.move(path("nope"), into: path("dest"))
        }
        let f = try tmp.file("a.txt")
        #expect(throws: FileActionError.volumeUnavailable("SourceSortMissingDisk")) {
            try FileActionService.move(f, into: URL(fileURLWithPath: "/Volumes/SourceSortMissingDisk/x"))
        }
        let blocker = try tmp.file("blocker")
        #expect(throws: FileActionError.notAFolder(blocker.path)) {
            try FileActionService.move(f, into: blocker)
        }
        #expect(FileManager.default.fileExists(atPath: f.path))  // untouched after failures
    }

    @Test func moveIntoSameFolderIsNoOp() throws {
        let f = try tmp.file("a.txt", in: "dl")
        #expect(try FileActionService.move(f, into: path("dl")) == f)
    }

    @Test func undoRestoresOriginal() throws {
        let original = try tmp.file("report.pdf", contents: "mine", in: "dl")
        let id = FileActionService.fileID(original)
        let moved = try FileActionService.move(original, into: path("dest"))
        let bookmark = FileActionService.bookmark(for: moved)

        let found = try #require(FileActionService.locate(path: moved.path, fileID: id, bookmark: bookmark))
        let restored = try FileActionService.restore(found, to: original)
        #expect(restored == original)
        #expect(contents(original) == "mine")
    }

    @Test func undoWhenOriginalNameTakenAndFolderDeleted() throws {
        let original = try tmp.file("report.pdf", contents: "mine", in: "dl")
        let moved = try FileActionService.move(original, into: path("dest"))
        try tmp.file("report.pdf", contents: "someone else", in: "dl")
        #expect(try FileActionService.restore(moved, to: original).lastPathComponent == "report 2.pdf")
        #expect(contents(original) == "someone else")

        let other = try tmp.file("b.txt", in: "gone")
        let moved2 = try FileActionService.move(other, into: path("dest"))
        try FileManager.default.removeItem(at: path("gone"))
        #expect(try FileActionService.restore(moved2, to: other) == other)  // folder recreated
    }

    @Test func undoFindsFileMovedAgainAndRejectsReplacements() throws {
        let original = try tmp.file("song.mp3", in: "dl")
        let moved = try FileActionService.move(original, into: path("dest"))
        let id = FileActionService.fileID(moved)
        let bookmark = FileActionService.bookmark(for: moved)

        // The user moved it elsewhere after sorting.
        let elsewhere = path("elsewhere/song.mp3")
        try FileManager.default.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: moved, to: elsewhere)
        // A different file now sits at the recorded path.
        try tmp.file("song.mp3", contents: "impostor", in: "dest")

        let found = try #require(FileActionService.locate(path: moved.path, fileID: id, bookmark: bookmark))
        #expect(found.standardizedFileURL.resolvingSymlinksInPath().path == elsewhere.resolvingSymlinksInPath().path)
    }

    @Test func undoOfDeletedFileFails() throws {
        let original = try tmp.file("gone.txt", in: "dl")
        let moved = try FileActionService.move(original, into: path("dest"))
        let id = FileActionService.fileID(moved)
        let bookmark = FileActionService.bookmark(for: moved)
        try FileManager.default.removeItem(at: moved)
        #expect(FileActionService.locate(path: moved.path, fileID: id, bookmark: bookmark) == nil)
    }

    @Test func tagsAndHandledMarker() throws {
        let f = try tmp.file("a.txt")
        try FileActionService.addTag("Invoices", to: f)
        try FileActionService.addTag("Invoices", to: f)
        #expect(try f.resourceValues(forKeys: [.tagNamesKey]).tagNames == ["Invoices"])
        #expect(!FileActionService.isHandled(f))
        FileActionService.markHandled(f)
        #expect(FileActionService.isHandled(f))
    }

    @Test func stabilityIgnoresTemporaryFiles() async throws {
        #expect(FileStabilityService.shouldIgnore(URL(fileURLWithPath: "/x/a.zip.crdownload")))
        #expect(FileStabilityService.shouldIgnore(URL(fileURLWithPath: "/x/a.zip.download")))
        #expect(FileStabilityService.shouldIgnore(URL(fileURLWithPath: "/x/.DS_Store")))
        #expect(!FileStabilityService.shouldIgnore(URL(fileURLWithPath: "/x/a.zip")))

        let f = try tmp.file("done.zip")
        #expect(await FileStabilityService(stableFor: 0.2, interval: 0.1).waitUntilStable(f))
        #expect(await !FileStabilityService(stableFor: 0.2, interval: 0.1).waitUntilStable(path("missing")))
    }

    @Test func jsonStoreRoundTripAndCorruptBackup() throws {
        let store = JSONStore(directory: path("store"))
        try store.save([WatchedFolder(path: "/a")], to: "folders.json")
        #expect(store.load([WatchedFolder].self, from: "folders.json")?.first?.path == "/a")
        var entry = ActivityEntry(fileName: "a.zip", source: DetectedSource(), rule: nil, originalPath: "/a.zip", outcome: .moved)
        entry.undoneDate = Date()
        try store.save([entry], to: "activity.json")
        #expect(store.load([ActivityEntry].self, from: "activity.json")?.first?.fileName == "a.zip")
        try Data("{broken".utf8).write(to: path("store/folders.json"))
        #expect(store.load([WatchedFolder].self, from: "folders.json") == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: path("store").path).contains { $0.contains("corrupt") })
    }
}

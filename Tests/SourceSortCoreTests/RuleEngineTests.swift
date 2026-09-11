import Foundation
import Testing
@testable import SourceSortCore

private func file(_ name: String, size: Int64 = 1000, from url: String? = nil, referrer: String? = nil, app: String? = nil, dir: Bool = false) -> FileMetadata {
    FileMetadata(
        url: URL(fileURLWithPath: "/Users/me/Downloads/\(name)"),
        isDirectory: dir,
        size: size,
        source: DetectedSource(originalURL: url.flatMap(URL.init(string:)), referrerURL: referrer.flatMap(URL.init(string:)), originatingApplication: app)
    )
}

private func rule(_ name: String, _ conditions: [RuleCondition], mode: ConditionMode = .all, enabled: Bool = true) -> Rule {
    Rule(name: name, isEnabled: enabled, conditions: conditions, conditionMode: mode, action: .move(to: "~/Sorted/\(name)"))
}

struct RuleEngineTests {
    let hf = file("model.gguf", size: 4_000_000_000, from: "https://cdn-lfs.huggingface.co/x/model.gguf", referrer: "https://huggingface.co/org/model")
    let gh = file("tool.dmg", from: "https://release-assets.githubusercontent.com/a/tool.dmg", referrer: "https://github.com/org/tool/releases", app: "Safari")
    let invoice = file("Invoice-2026.PDF", size: 200_000, from: "https://billing.example.com/inv?id=1")

    @Test func domainIsMatchesSubdomainsAndReferrer() {
        #expect(RuleEngine.matches(RuleCondition(.sourceDomain, .is, "huggingface.co"), hf))
        #expect(RuleEngine.matches(RuleCondition(.sourceDomain, .is, "github.com"), gh))
        #expect(RuleEngine.matches(RuleCondition(.sourceDomain, .is, "githubusercontent.com"), gh))  // download host counts too
        #expect(RuleEngine.matches(RuleCondition(.sourceDomain, .is, "www.GitHub.com"), gh))
        #expect(!RuleEngine.matches(RuleCondition(.sourceDomain, .is, "hub.com"), gh))  // no partial-label match
        #expect(RuleEngine.matches(RuleCondition(.sourceDomain, .contains, "hugging"), hf))
        #expect(RuleEngine.matches(RuleCondition(.sourceDomain, .is, "example.org, example.com"), invoice))
    }

    @Test func fileWithoutSourceNeverMatchesSourceConditions() {
        let plain = file("notes.txt")
        #expect(!RuleEngine.matches(RuleCondition(.sourceDomain, .contains, ""), plain))
        #expect(!RuleEngine.matches(RuleCondition(.sourceURL, .contains, "http"), plain))
        #expect(!RuleEngine.matches(RuleCondition(.originatingApplication, .is, "Safari"), plain))
    }

    @Test func textConditionsAreCaseInsensitive() {
        #expect(RuleEngine.matches(RuleCondition(.fileName, .startsWith, "invoice"), invoice))
        #expect(RuleEngine.matches(RuleCondition(.fileName, .endsWith, ".pdf"), invoice))
        #expect(RuleEngine.matches(RuleCondition(.fileName, .contains, "2026"), invoice))
        #expect(RuleEngine.matches(RuleCondition(.fileName, .is, "invoice-2026.pdf"), invoice))
        #expect(RuleEngine.matches(RuleCondition(.fileExtension, .is, ".pdf"), invoice))
        #expect(RuleEngine.matches(RuleCondition(.fileExtension, .is, "gguf, safetensors"), hf))
        #expect(RuleEngine.matches(RuleCondition(.sourceURL, .contains, "/RELEASES"), gh))
        #expect(RuleEngine.matches(RuleCondition(.originatingApplication, .is, "safari"), gh))
    }

    @Test func fileTypeAndSize() {
        #expect(RuleEngine.matches(RuleCondition(.fileType, .is, FileKind.pdf.rawValue), invoice))
        #expect(RuleEngine.matches(RuleCondition(.fileType, .is, FileKind.diskImage.rawValue), gh))
        #expect(!RuleEngine.matches(RuleCondition(.fileType, .is, FileKind.image.rawValue), invoice))
        #expect(RuleEngine.matches(RuleCondition(.fileType, .is, FileKind.folder.rawValue), file("Repo", dir: true)))
        #expect(RuleEngine.matches(RuleCondition(.fileSize, .greaterThan, "1000"), hf))       // 4 GB > 1000 MB
        #expect(RuleEngine.matches(RuleCondition(.fileSize, .lessThan, "0,5"), invoice))       // 0.2 MB < 0.5 MB
        #expect(!RuleEngine.matches(RuleCondition(.fileSize, .greaterThan, "abc"), hf))
    }

    @Test func allVersusAny() {
        let conditions = [RuleCondition(.sourceDomain, .is, "huggingface.co"), RuleCondition(.fileExtension, .is, "zip")]
        #expect(!RuleEngine.matches(rule("all", conditions), hf))
        #expect(RuleEngine.matches(rule("any", conditions, mode: .any), hf))
    }

    @Test func firstEnabledMatchWinsAndEmptyRulesNeverMatch() {
        let rules = [
            rule("empty", []),
            rule("disabled", [RuleCondition(.sourceDomain, .is, "github.com")], enabled: false),
            rule("github", [RuleCondition(.sourceDomain, .is, "github.com")]),
            rule("dmg", [RuleCondition(.fileExtension, .is, "dmg")]),
        ]
        #expect(RuleEngine.firstMatch(in: rules, for: gh)?.name == "github")
        #expect(RuleEngine.firstMatch(in: rules, for: file("x.dmg"))?.name == "dmg")
        #expect(RuleEngine.firstMatch(in: rules, for: file("x.txt")) == nil)
    }

    @Test func renameTemplate() {
        var action = RuleAction.move(to: "~/Models")
        action.renameTemplate = "{domain} - {name}"
        #expect(action.targetName(for: hf) == "huggingface.co - model.gguf")
        action.renameTemplate = "{name} {date}"
        let date = ISO8601DateFormatter().date(from: "2026-03-04T12:00:00Z")!
        #expect(action.targetName(for: file("a.tar.gz"), date: date) == "a 2026-03-04.tar.gz")
        action.renameTemplate = ""
        #expect(action.targetName(for: hf) == nil)
        #expect(RuleAction.move(to: "~/X").destinationURL?.path == NSHomeDirectory() + "/X")
    }
}

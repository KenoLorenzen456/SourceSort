import AppKit
import SourceSortCore
import SwiftUI

/// README screenshots: `SOURCESORT_SNAPSHOTS=<dir> SourceSort.app/Contents/MacOS/SourceSort`
/// runs on demo data stored in <dir> (never your real rules, history or folders), saves PNGs there and quits.
@MainActor
enum Snapshots {
    static let directory = ProcessInfo.processInfo.environment["SOURCESORT_SNAPSHOTS"].map { URL(fileURLWithPath: $0, isDirectory: true) }

    static func run(_ model: AppModel) async {
        guard let dir = directory else { return }
        NSApp.appearance = NSAppearance(named: .aqua) // vibrant sidebar text renders unreadable in dark mode offscreen
        model.rules = OnboardingView.starterRules.map(\.rule)
        model.activity = demoActivity
        try? await Task.sleep(for: .seconds(1))
        model.showMainWindow(.rules)
        for section in SidebarSection.allCases {
            model.section = section
            try? await Task.sleep(for: .seconds(1.5))
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }), let frame = window.contentView?.superview {
                save(frame, dir.appendingPathComponent("\(section.rawValue).png"))
            }
        }
        let popover = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        let host = NSHostingView(rootView: MenuBarView().environment(model))
        popover.contentView = host
        popover.setContentSize(host.fittingSize)
        popover.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(1))
        save(host, dir.appendingPathComponent("menu-bar.png"))
        NSApp.terminate(nil)
    }

    private static func save(_ view: NSView, _ url: URL) {
        // Renders the layer tree (cacheDisplay misses SwiftUI text); materials come out flat, so paint the window background first.
        guard let layer = view.layer, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.current = context
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            view.bounds.fill()
        }
        let cg = context.cgContext
        if view.isFlipped { cg.translateBy(x: 0, y: view.bounds.height); cg.scaleBy(x: 1, y: -1) }
        // Backdrop (vibrancy) layers can't be rendered offscreen and come out white; hide them so the fill shows.
        let offscreenless = ["Backdrop", "SDF", "Chameleon", "Portal"]
        let backdrops = allLayers(layer).filter { layer in
            !layer.isHidden && (offscreenless.contains { "\(type(of: layer))".contains($0) } || (layer.compositingFilter != nil && layer.contents == nil))
        }
        backdrops.forEach { $0.isHidden = true }
        layer.render(in: cg)
        backdrops.forEach { $0.isHidden = false }
        NSGraphicsContext.current = nil
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func allLayers(_ layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap(allLayers)
    }

    private static var demoActivity: [ActivityEntry] {
        let rules = OnboardingView.starterRules.map(\.rule)
        func entry(_ name: String, _ from: String, _ rule: Int?, _ outcome: ActivityEntry.Outcome, minutesAgo: Double, to folder: String? = nil) -> ActivityEntry {
            var e = ActivityEntry(fileName: name, source: DetectedSource(originalURL: URL(string: from)),
                                  rule: rule.map { rules[$0] }, originalPath: "/Users/demo/Downloads/\(name)", outcome: outcome)
            e.date = Date().addingTimeInterval(-minutesAgo * 60)
            e.newPath = folder.map { "/Users/demo/Downloads/\($0)/\(name)" }
            return e
        }
        return [
            entry("llama-3-8b-instruct.Q4_K_M.gguf", "https://huggingface.co/meta-llama/resolve/main/model.gguf", 1, .moved, minutesAgo: 2, to: "Models"),
            entry("Hello-World-main.zip", "https://github.com/octocat/Hello-World/archive/main.zip", 0, .moved, minutesAgo: 14, to: "GitHub"),
            entry("invoice-2026-09.pdf", "https://pay.stripe.com/invoice/pdf", 3, .tagged, minutesAgo: 38),
            entry("Firefox 131.0.dmg", "https://download-installer.cdn.mozilla.net/pub/firefox/Firefox.dmg", 2, .moved, minutesAgo: 65, to: "Installers"),
            entry("quarterly-report.xlsx", "https://docs.google.com/spreadsheets/export", nil, .noMatch, minutesAgo: 120),
            entry("ripgrep-14.1.0-aarch64.tar.gz", "https://github.com/BurntSushi/ripgrep/releases/download/14.1.0/rg.tar.gz", 0, .moved, minutesAgo: 190, to: "GitHub"),
        ]
    }
}

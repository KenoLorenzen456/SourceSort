import SourceSortCore
import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var ruleFilter = RuleFilter.all
    @State private var sourceFilter = ""
    @State private var selection = Set<ActivityEntry.ID>()
    @State private var confirmClear = false

    enum RuleFilter: Hashable {
        case all, none, rule(String)
    }

    private var entries: [ActivityEntry] {
        model.activity.filter { e in
            switch ruleFilter {
            case .all: break
            case .none: if e.ruleName != nil { return false }
            case .rule(let name): if e.ruleName != name { return false }
            }
            if !sourceFilter.isEmpty, e.sourceDomain != sourceFilter { return false }
            guard !search.isEmpty else { return true }
            return [e.fileName, e.sourceDomain, e.sourceURL, e.ruleName, e.newPath].contains { $0?.localizedCaseInsensitiveContains(search) == true }
        }
    }

    var body: some View {
        Group {
            if model.activity.isEmpty {
                ContentUnavailableView("No Activity", systemImage: "clock",
                                       description: Text("Downloads SourceSort sees will appear here, with a way to undo every move."))
            } else if entries.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                table
            }
        }
        .navigationTitle("Activity")
        .searchable(text: $search, prompt: "File, source or rule")
        .toolbar {
            ToolbarItemGroup {
                Picker("Rule", selection: $ruleFilter) {
                    Text("All Rules").tag(RuleFilter.all)
                    Text("No Match").tag(RuleFilter.none)
                    Divider()
                    ForEach(ruleNames, id: \.self) { Text($0).tag(RuleFilter.rule($0)) }
                }
                Picker("Source", selection: $sourceFilter) {
                    Text("All Sources").tag("")
                    Divider()
                    ForEach(sources, id: \.self) { Text($0).tag($0) }
                }
                Button("Clear History", systemImage: "trash") { confirmClear = true }
                    .disabled(model.activity.isEmpty)
            }
        }
        .confirmationDialog("Clear all activity?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.clearHistory() }
        } message: {
            Text("Your files stay where they are, but moves can no longer be undone.")
        }
    }

    private var table: some View {
        Table(entries, selection: $selection) {
            TableColumn("File") { e in
                HStack(spacing: 8) {
                    Image(nsImage: e.icon).resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                    Text(e.fileName).lineLimit(1).truncationMode(.middle)
                }
                .help(e.sourceURL ?? "")
            }
            .width(min: 140, ideal: 200)
            TableColumn("Source") { e in Text(e.sourceDomain ?? "Unknown").foregroundStyle(e.sourceDomain == nil ? .secondary : .primary) }
                .width(min: 70, ideal: 100)
            TableColumn("Rule") { e in Text(e.ruleName ?? "—").foregroundStyle(e.ruleName == nil ? .secondary : .primary) }
                .width(min: 60, ideal: 90)
            TableColumn("Result") { e in
                Text(e.resultText)
                    .foregroundStyle(e.outcome == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .help(e.newPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? e.errorMessage ?? "")
            }
            .width(min: 90, ideal: 130)
            TableColumn("Date") { e in Text(e.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
                .width(min: 80, ideal: 110)
            TableColumn("") { e in
                if e.canUndo {
                    Button("Undo") { model.undo(e) }
                        .controlSize(.small)
                        .accessibilityLabel("Undo moving \(e.fileName)")
                }
            }
            .width(56)
        }
        .contextMenu(forSelectionType: ActivityEntry.ID.self) { ids in
            let chosen = model.activity.filter { ids.contains($0.id) }
            Button("Show in Finder") { chosen.forEach { $0.revealInFinder() } }
            Button("Undo") { chosen.filter(\.canUndo).forEach(model.undo) }
                .disabled(!chosen.contains(where: \.canUndo))
        } primaryAction: { ids in
            model.activity.filter { ids.contains($0.id) }.forEach { $0.revealInFinder() }
        }
    }

    private var ruleNames: [String] { Array(Set(model.activity.compactMap(\.ruleName))).sorted() }
    private var sources: [String] { Array(Set(model.activity.compactMap(\.sourceDomain))).sorted() }
}

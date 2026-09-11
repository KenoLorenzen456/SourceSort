import SourceSortCore
import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Rule?
    @State private var selection: Rule.ID?

    var body: some View {
        @Bindable var model = model
        Group {
            if model.rules.isEmpty {
                ContentUnavailableView {
                    Label("No Rules", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Rules decide where downloads go, based on the website they came from, their name, type or size.")
                } actions: {
                    Button("New Rule") { editing = Self.newRule() }.buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $selection) {
                    Section {
                        ForEach($model.rules) { $rule in
                            RuleRow(rule: $rule).tag(rule.id)
                        }
                        .onMove { model.rules.move(fromOffsets: $0, toOffset: $1) }
                    } footer: {
                        Text("Rules run from top to bottom and the first match wins. Drag to change the order.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contextMenu(forSelectionType: Rule.ID.self) { ids in
                    if let id = ids.first, let rule = model.rules.first(where: { $0.id == id }) {
                        Button("Edit…") { editing = rule }
                        Button("Duplicate") { duplicate(rule) }
                        Divider()
                        Button("Delete", role: .destructive) { delete(id) }
                    }
                } primaryAction: { ids in
                    editing = ids.first.flatMap { id in model.rules.first { $0.id == id } }
                }
                .onDeleteCommand { if let selection { delete(selection) } }
            }
        }
        .navigationTitle("Rules")
        .toolbar {
            ToolbarItemGroup {
                Button("Edit Rule", systemImage: "pencil") {
                    editing = model.rules.first { $0.id == selection }
                }
                .disabled(selection == nil)
                .keyboardShortcut(.return, modifiers: .command)
                Button("New Rule", systemImage: "plus") { editing = Self.newRule() }
                    .keyboardShortcut("n")
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule) { saved in
                if let i = model.rules.firstIndex(where: { $0.id == saved.id }) {
                    model.rules[i] = saved
                } else {
                    model.rules.append(saved)
                }
                selection = saved.id
            }
        }
    }

    static func newRule() -> Rule {
        Rule(name: "", conditions: [RuleCondition(.sourceDomain, .is, "")], action: .move(to: ""))
    }

    private func duplicate(_ rule: Rule) {
        var copy = rule
        copy.id = UUID()
        copy.name += " Copy"
        copy.conditions = copy.conditions.map { var c = $0; c.id = UUID(); return c }
        let index = model.rules.firstIndex(of: rule).map { $0 + 1 } ?? model.rules.endIndex
        model.rules.insert(copy, at: index)
    }

    private func delete(_ id: Rule.ID) {
        model.rules.removeAll { $0.id == id }
        selection = nil
    }
}

private struct RuleRow: View {
    @Binding var rule: Rule

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Enabled", isOn: $rule.isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("Enable \(rule.name)")
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name.isEmpty ? "Untitled Rule" : rule.name).font(.body.weight(.medium))
                HStack(spacing: 4) {
                    Text(rule.conditionSummary.isEmpty ? "No conditions" : rule.conditionSummary)
                    Image(systemName: "arrow.right").imageScale(.small).accessibilityLabel("then")
                    Text(rule.action.summary)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
        }
        .opacity(rule.isEnabled ? 1 : 0.55)
        .padding(.vertical, 3)
    }
}

struct RuleEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var rule: Rule
    let onSave: (Rule) -> Void
    @State private var test: TestResult?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $rule.name, prompt: Text("e.g. GitHub Downloads"))

                Section("Conditions") {
                    Picker("Match", selection: $rule.conditionMode) {
                        Text("All conditions").tag(ConditionMode.all)
                        Text("Any condition").tag(ConditionMode.any)
                    }
                    ForEach($rule.conditions) { $condition in
                        ConditionRow(condition: $condition) {
                            rule.conditions.removeAll { $0.id == condition.id }
                        }
                    }
                    Button("Add Condition", systemImage: "plus") {
                        rule.conditions.append(RuleCondition(.fileExtension, .is, ""))
                    }
                }

                Section("Action") {
                    Picker("Action", selection: $rule.action.kind) {
                        ForEach(RuleAction.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    switch rule.action.kind {
                    case .move:
                        LabeledContent("Destination") {
                            HStack {
                                TextField("Destination", text: $rule.action.destinationPath, prompt: Text("~/Downloads/GitHub"))
                                    .labelsHidden()
                                Button("Choose…") {
                                    if let url = model.chooseFolder(message: "Choose where matching files go.", startingAt: rule.action.destinationPath.isEmpty ? "~" : rule.action.destinationPath) {
                                        rule.action.destinationPath = (url.path as NSString).abbreviatingWithTildeInPath
                                    }
                                }
                            }
                        }
                        TextField(text: $rule.action.renameTemplate, prompt: Text("Keep original name")) {
                            Text("Rename to")
                            Text("Optional. Use {name}, {domain} and {date}. The extension is kept.")
                        }
                    case .addTag:
                        TextField("Tag", text: $rule.action.tagName, prompt: Text("e.g. Invoice"))
                    case .leaveInPlace:
                        Text("Matching files stay where they are, and rules below this one are skipped.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Test") {
                    LabeledContent {
                        Button("Choose File…") { runTest() }
                    } label: {
                        Text("Test Rule")
                        Text("Pick a file to see what this rule would do. Nothing is moved.")
                    }
                    if let test { TestResultView(result: test) }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let problem { Text(problem).font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    rule.name = rule.name.trimmingCharacters(in: .whitespaces)
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
            .padding()
        }
        .frame(width: 580, height: 620)
    }

    private var problem: String? {
        if rule.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the rule a name." }
        if rule.conditions.isEmpty { return "Add at least one condition." }
        if rule.conditions.contains(where: { $0.values.isEmpty }) { return "Fill in every condition." }
        if rule.action.kind == .move, rule.action.destinationURL == nil { return "Choose a destination folder." }
        if rule.action.kind == .addTag, rule.action.tagName.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a tag." }
        return nil
    }

    private func runTest() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.directoryURL = model.folders.first?.url
        panel.message = "Choose a file to test “\(rule.name.isEmpty ? "this rule" : rule.name)” against."
        guard panel.runModal() == .OK, let url = panel.url, let file = try? FileMetadata.read(url) else { return }
        test = TestResult(rule: rule, file: file)
    }
}

private struct ConditionRow: View {
    @Binding var condition: RuleCondition
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Picker("Field", selection: $condition.field) {
                ForEach(ConditionField.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            if condition.field.operators.count > 1 {
                Picker("Operator", selection: $condition.op) {
                    ForEach(condition.field.operators, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            } else {
                Text(condition.op.title).foregroundStyle(.secondary)
            }
            if condition.field == .fileType {
                Picker("Type", selection: $condition.value) {
                    ForEach(FileKind.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
            } else {
                TextField("Value", text: $condition.value, prompt: Text(condition.field.placeholder))
                    .labelsHidden()
                    .help(condition.field == .fileSize ? "Megabytes" : "Separate several values with commas; any of them can match.")
            }
            Button("Remove Condition", systemImage: "minus.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .onChange(of: condition.field) { _, field in
            if !field.operators.contains(condition.op) { condition.op = field.operators[0] }
            if field == .fileType, FileKind(rawValue: condition.value) == nil { condition.value = FileKind.image.rawValue }
            if field != .fileType, FileKind(rawValue: condition.value) != nil { condition.value = "" }
        }
    }
}

struct TestResult {
    let rule: Rule
    let file: FileMetadata
    var matches: Bool { RuleEngine.matches(rule, file) }
}

private struct TestResultView: View {
    let result: TestResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(result.file.fileName, systemImage: "doc").font(.headline)
            Text(sourceText).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            ForEach(result.rule.conditions) { condition in
                let ok = RuleEngine.matches(condition, result.file)
                Label(condition.field.title + " " + condition.summary, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? .green : .secondary)
                    .accessibilityLabel("\(condition.field.title) \(condition.summary): \(ok ? "matches" : "does not match")")
            }
            Text(outcome).font(.callout.weight(.medium))
        }
        .padding(.vertical, 4)
    }

    private var sourceText: String {
        let s = result.file.source
        var lines = ["Source: \(s.domain ?? "unknown")"]
        if let url = s.originalURL { lines.append("Downloaded from: \(url.absoluteString)") }
        if let app = s.originatingApplication { lines.append("Downloaded by: \(app)") }
        return lines.joined(separator: "\n")
    }

    private var outcome: String {
        guard result.matches else { return "This rule would not match." }
        let action = result.rule.action
        switch action.kind {
        case .move:
            let name = action.targetName(for: result.file) ?? result.file.fileName
            return "Would move to \(action.destinationPath) as “\(name)”."
        case .addTag: return "Would add the tag “\(action.tagName)”."
        case .leaveInPlace: return "Would leave the file in place."
        }
    }
}

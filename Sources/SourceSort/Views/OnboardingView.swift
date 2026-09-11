import SourceSortCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var chosen: Set<String> = ["GitHub", "Hugging Face", "Installers"]

    static let starterRules: [(rule: Rule, detail: String)] = [
        (Rule(name: "GitHub", conditions: [RuleCondition(.sourceDomain, .is, "github.com, githubusercontent.com")],
              action: .move(to: "~/Downloads/GitHub")), "Releases and repositories → Downloads/GitHub"),
        (Rule(name: "Hugging Face", conditions: [RuleCondition(.sourceDomain, .is, "huggingface.co, hf.co")],
              action: .move(to: "~/Downloads/Models")), "Models and datasets → Downloads/Models"),
        (Rule(name: "Installers", conditions: [RuleCondition(.fileType, .is, FileKind.diskImage.rawValue), RuleCondition(.fileType, .is, FileKind.installer.rawValue)],
              conditionMode: .any, action: .move(to: "~/Downloads/Installers")), "Disk images and installers → Downloads/Installers"),
        (Rule(name: "Invoices", conditions: [RuleCondition(.fileName, .contains, "invoice, receipt, rechnung"), RuleCondition(.fileExtension, .is, "pdf")],
              action: RuleAction(kind: .addTag, tagName: "Invoice")), "PDFs named invoice or receipt → tagged “Invoice”"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: setup
                default: finish
                }
            }
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)

            Divider()
            HStack {
                Text("Step \(step + 1) of 3").foregroundStyle(.secondary)
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                Button(step == 2 ? "Start Sorting" : "Continue") {
                    if step < 2 { step += 1 } else { complete() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(step == 1 && model.folders.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96).accessibilityHidden(true)
            Text("Welcome to SourceSort").font(.largeTitle.bold())
            Text("SourceSort files your downloads by the website they came from, and by name, type or size.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Label("Rules like “everything from GitHub goes to GitHub”", systemImage: "arrow.triangle.branch")
                Label("Every move shows up in the menu bar and can be undone", systemImage: "arrow.uturn.backward")
                Label(privacyStatement, systemImage: "lock.shield")
            }
            .padding(.top, 6)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Watch").font(.title2.bold())
            HStack {
                Label(model.folders.map(\.displayPath).joined(separator: ", "), systemImage: "folder")
                Spacer()
                Button("Change…") {
                    if let url = model.chooseFolder(message: "Choose the folder your browser downloads to.", startingAt: model.folders.first?.path) {
                        model.replaceFolders(with: url)
                    }
                }
            }
            Text("Start with these rules").font(.title2.bold()).padding(.top, 8)
            ForEach(Self.starterRules, id: \.rule.name) { starter in
                Toggle(isOn: Binding(
                    get: { chosen.contains(starter.rule.name) },
                    set: { if $0 { chosen.insert(starter.rule.name) } else { chosen.remove(starter.rule.name) } }
                )) {
                    Text(starter.rule.name)
                    Text(starter.detail)
                }
                .toggleStyle(.checkbox)
            }
            Text("You can change or add rules at any time.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var finish: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 16) {
            Text("You’re all set").font(.title2.bold())
            Text("SourceSort lives in the menu bar. Click its icon to see recent downloads and undo moves.")
                .foregroundStyle(.secondary)
            Form {
                LaunchAtLoginToggle()
                Toggle("Show notifications when files are sorted", isOn: $model.notificationsEnabled)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 110)
            SafariTip()
        }
    }

    private func complete() {
        if model.rules.isEmpty {
            model.rules = Self.starterRules.map(\.rule).filter { chosen.contains($0.name) }
        }
        model.onboardingDone = true
        model.section = model.rules.isEmpty ? .rules : .activity
    }
}

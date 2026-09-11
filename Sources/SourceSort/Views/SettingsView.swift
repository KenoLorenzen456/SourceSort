import ServiceManagement
import SourceSortCore
import SwiftUI

let privacyStatement = "SourceSort processes file metadata locally on your Mac. Nothing is uploaded."

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        @Bindable var model = model
        Form {
            Section("General") {
                LaunchAtLoginToggle()
                Toggle(isOn: $showMenuBarIcon) {
                    Text("Show in menu bar")
                    Text("When hidden, open SourceSort from the Applications folder to see this window.")
                }
                Toggle("Show notifications", isOn: $model.notificationsEnabled)
            }

            Section {
                ForEach(model.folders) { folder in
                    HStack {
                        Label(folder.displayPath, systemImage: "folder")
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") {
                            model.folders.removeAll { $0.id == folder.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Stop watching \(folder.displayPath)")
                    }
                }
                Button("Add Folder…", systemImage: "plus") { model.addFolder() }
            } header: {
                Text("Watched Folders")
            } footer: {
                Text("Only files added directly to these folders are sorted. Files already there are left alone.")
            }

            Section("Sorting") {
                Toggle(isOn: $model.onlyDownloadedFiles) {
                    Text("Only sort downloaded files")
                    Text("Ignore files you create or save yourself, which have no download information.")
                }
                Picker("Wait before sorting", selection: $model.stabilitySeconds) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                }
                Picker("Keep history", selection: $model.retentionDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(0)
                }
            }

            Section("Pausing") {
                Toggle(isOn: $model.isPaused) {
                    Text("Pause sorting")
                    Text("Files downloaded while paused are ignored and stay where they are, even after you resume.")
                }
            }

            Section("Privacy") {
                Label(privacyStatement, systemImage: "lock.shield")
                SafariTip()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status

    var body: some View {
        Toggle("Open at login", isOn: Binding(
            get: { status == .enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    AppModel.shared.alert("Couldn’t change the login item", error.localizedDescription)
                }
                status = SMAppService.mainApp.status
            }
        ))
        if status == .requiresApproval {
            HStack {
                Text("Allow SourceSort in System Settings to open it at login.").foregroundStyle(.secondary)
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
    }
}

struct SafariTip: View {
    var body: some View {
        Label {
            Text("Using Safari? Turn off **Open “safe” files after downloading** in Safari ▸ Settings ▸ General. Otherwise Safari unpacks archives and the unpacked folder loses its source website.")
        } icon: {
            Image(systemName: "safari")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

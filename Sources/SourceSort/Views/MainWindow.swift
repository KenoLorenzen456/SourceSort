import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        Group {
            if model.onboardingDone {
                NavigationSplitView {
                    List(SidebarSection.allCases, selection: $model.section) { section in
                        Label(section.title, systemImage: section.icon).tag(section)
                    }
                    .navigationSplitViewColumnWidth(min: 160, ideal: 180)
                } detail: {
                    switch model.section {
                    case .rules: RulesView()
                    case .activity: ActivityView()
                    case .settings: SettingsView()
                    }
                }
                .frame(minWidth: 720, minHeight: 440)
            } else {
                OnboardingView()
            }
        }
        // A menu bar app shows in the Dock and app switcher only while its window is open.
        .onAppear {
            model.openWindowAction = { openWindow(id: "main") }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

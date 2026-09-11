import SwiftUI
import UserNotifications

@main
struct SourceSortApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView().environment(model)
        } label: {
            MenuBarLabel(paused: model.isPaused)
        }
        .menuBarExtraStyle(.window)

        Window("SourceSort", id: "main") {
            MainWindow().environment(model)
        }
        .defaultSize(width: 860, height: 560)
        .windowResizability(.contentMinSize)
        // Shown at launch only when there is no other way in: first run, or the menu bar icon is hidden.
        .defaultLaunchBehavior(model.onboardingDone && showMenuBarIcon ? .suppressed : .presented)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.showMainWindow(.settings) }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu("View") {
                ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { i, section in
                    Button(section.title) { model.showMainWindow(section) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
            }
        }
    }
}

struct MenuBarLabel: View {
    let paused: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: paused ? "tray" : "tray.and.arrow.down.fill")
            .accessibilityLabel(paused ? "SourceSort, paused" : "SourceSort")
            .onAppear { AppModel.shared.openWindowAction = { openWindow(id: "main") } }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        AppModel.shared.start()
    }

    /// Opening the app again (Finder, Spotlight, Dock) shows the main window — the way back in if the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        AppModel.shared.showMainWindow()
        return false
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { AppModel.shared.showMainWindow(.activity) }
    }
}

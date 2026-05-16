import SwiftUI
import UserNotifications

@main
struct PurpurManagerApp: App {
    @State private var appModel = AppModel()
    @State private var preferences = AppPreferences()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(preferences)
                .preferredColorScheme(preferences.theme.colorScheme)
                .tint(preferences.accent.color)
                .task {
                    await NotificationService.shared.requestAuthorization()
                    appModel.connectAllAuto()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandMenu("Server") {
                Button("Connect") { appModel.connectSelected() }
                    .keyboardShortcut("k", modifiers: [.command])
                Button("Disconnect") { appModel.disconnectSelected() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Save Server") { appModel.selectedRuntime?.saveServer() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        Settings {
            AppSettingsView()
                .environment(appModel)
                .environment(preferences)
                .frame(width: 720, height: 620)
        }

        MenuBarExtra("Purpur Manager", systemImage: "server.rack") {
            MenuBarStatusView()
                .environment(appModel)
                .environment(preferences)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

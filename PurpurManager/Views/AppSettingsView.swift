import SwiftUI

struct AppSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var preferences = preferences
        TabView {
            Form {
                Section("Appearance") {
                    Picker("Accent", selection: $preferences.accent) {
                        ForEach(AccentPreference.allCases) { accent in
                            Label(accent.label, systemImage: "circle.fill")
                                .foregroundStyle(accent.color)
                                .tag(accent)
                        }
                    }
                    Picker("Theme", selection: $preferences.theme) {
                        ForEach(ThemePreference.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Compact mode", isOn: $preferences.compactMode)
                    Toggle("Reduced motion", isOn: $preferences.reducedMotion)
                    Slider(value: $preferences.sidebarWidth, in: 220...360) { Text("Sidebar width") }
                    Slider(value: $preferences.fontScale, in: 0.85...1.25) { Text("Font size") }
                }
                Section("Dashboard Widgets") {
                    Toggle("Memory graph", isOn: $preferences.showMemoryWidget)
                    Toggle("Player graph", isOn: $preferences.showPlayerWidget)
                    Toggle("Latency graph", isOn: $preferences.showLatencyWidget)
                }
                Button("Reset Appearance") { preferences.reset() }
            }
            .padding(20)
            .tabItem { Label("General", systemImage: "paintpalette.fill") }

            Form {
                Section("Connections") {
                    Toggle("Global auto reconnect", isOn: $preferences.globalAutoReconnect)
                    Slider(value: $preferences.refreshInterval, in: 2...30, step: 1) {
                        Text("Refresh interval")
                    } minimumValueLabel: { Text("2s") } maximumValueLabel: { Text("30s") }
                    Text("Current interval: \(Int(preferences.refreshInterval)) seconds")
                        .foregroundStyle(.secondary)
                }
                Section("Startup") {
                    Toggle("Launch into menu bar mode", isOn: $preferences.launchMenuBarOnly)
                }
                Section("Server Configs") {
                    Button("Import Server Configs") { appModel.importServers() }
                    Button("Export Server Configs") { appModel.exportServers() }
                }
            }
            .padding(20)
            .tabItem { Label("Connections", systemImage: "antenna.radiowaves.left.and.right") }

            Form {
                Section("Notifications") {
                    Toggle("Show notifications while app is foreground", isOn: $preferences.notifyInForeground)
                    Text("Per-server notification preferences are configured in each server editor. Native macOS notifications are delivered through UserNotifications.")
                        .foregroundStyle(.secondary)
                }
                Section("Future Integrations") {
                    Label("Discord webhook integration seam", systemImage: "bubble.left.and.bubble.right.fill")
                    Label("Home Assistant and Shortcuts hooks", systemImage: "house.fill")
                    Label("Sparkle updater support architecture", systemImage: "sparkles")
                }
            }
            .padding(20)
            .tabItem { Label("Notifications", systemImage: "bell.badge.fill") }
        }
    }
}

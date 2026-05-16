import SwiftUI

struct MenuBarStatusView: View {
    @Environment(AppModel.self) private var appModel
    @State private var broadcastText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Purpur Manager", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                Button("Open Dashboard") { NSApp.activate(ignoringOtherApps: true) }
            }
            Divider()
            if appModel.profiles.isEmpty {
                ContentUnavailableView("No servers", systemImage: "server.rack")
            } else {
                ForEach(appModel.profiles) { profile in
                    let runtime = appModel.runtime(for: profile)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(profile.displayName).fontWeight(.semibold)
                                Text("\(runtime.state.label) • \(runtime.status.playerCount ?? runtime.players.count) players")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle().fill(runtime.state.tint).frame(width: 10, height: 10)
                        }
                        HStack {
                            Button("Reconnect") { runtime.reconnectNow() }
                            Button("Save") { runtime.saveServer() }
                            Button("Stop") { runtime.stopServer() }.foregroundStyle(.red)
                        }
                        HStack {
                            TextField("Broadcast message", text: $broadcastText)
                            Button("Send") { runtime.broadcastSystemMessage(broadcastText, overlay: false); broadcastText = "" }
                                .disabled(broadcastText.isEmpty)
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}

import SwiftUI

struct ServerSidebarView: View {
    @Environment(AppModel.self) private var appModel
    @Binding var showingAddServer: Bool
    @State private var editingProfile: ServerProfile?

    var body: some View {
        @Bindable var appModel = appModel
        List(selection: $appModel.selectedServerID) {
            Section {
                ForEach(appModel.groupedProfiles, id: \.0) { group, profiles in
                    if appModel.groupedProfiles.count > 1 {
                        Text(group).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(profiles) { profile in
                        ServerRow(profile: profile, runtime: appModel.runtime(for: profile))
                            .tag(profile.id)
                            .contextMenu {
                                Button("Connect") { appModel.runtime(for: profile).connect() }
                                Button("Disconnect") { appModel.runtime(for: profile).disconnect(manual: true) }
                                Divider()
                                Button("Edit…") { editingProfile = profile }
                                Button("Remove", role: .destructive) { appModel.removeServer(profile) }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("Servers")
                    Spacer()
                    Button("Add", systemImage: "plus") { showingAddServer = true }
                        .buttonStyle(.borderless)
                }
            }

            Section("Manage") {
                Button { appModel.connectAll() } label: { Label("Connect All", systemImage: "bolt.fill") }
                Button { appModel.disconnectAll() } label: { Label("Disconnect All", systemImage: "power") }
                Button { appModel.importServers() } label: { Label("Import Configs", systemImage: "square.and.arrow.down") }
                Button { appModel.exportServers() } label: { Label("Export Configs", systemImage: "square.and.arrow.up") }
            }

            Section("IP Whitelist Helper") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Management API listens on the server host and port you configured.", systemImage: "lock.shield")
                    Text("If the server uses a firewall, allow this Mac's LAN/VPN IP and keep API tokens scoped to management use only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Server", systemImage: "plus") { showingAddServer = true }
            }
        }
        .sheet(item: $editingProfile) { profile in
            ServerEditorView(mode: .edit(profile))
                .environment(appModel)
        }
    }
}

private struct ServerRow: View {
    var profile: ServerProfile
    var runtime: ServerRuntime

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [.purple.opacity(0.9), .blue.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                Image(systemName: "cube.fill")
                    .font(.callout)
                    .foregroundStyle(.white)
                Circle()
                    .fill(runtime.state.tint)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
                    .offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(runtime.healthSummary)
                    if let count = runtime.status.playerCount {
                        Text("•")
                        Text("\(count) players")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

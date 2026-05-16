import SwiftUI

struct PlayerManagementView: View {
    let runtime: ServerRuntime
    @State private var searchText = ""
    @State private var selection = Set<MCPlayer.ID>()
    @State private var messageText = ""
    @State private var kickReason = "Kicked by an operator"

    private var filteredPlayers: [MCPlayer] {
        guard !searchText.isEmpty else { return runtime.players }
        return runtime.players.filter { player in
            player.name.localizedCaseInsensitiveContains(searchText) || (player.uuid?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.35)
            if runtime.players.isEmpty {
                ContentUnavailableView("No Online Players", systemImage: "person.2.slash", description: Text("Connected player data appears here when the server exposes player list RPC methods."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredPlayers, selection: $selection) {
                    TableColumn("Player") { player in
                        HStack {
                            Image(systemName: player.isOperator ? "crown.fill" : "person.crop.square.fill")
                                .foregroundStyle(player.isOperator ? .orange : .blue)
                            VStack(alignment: .leading) {
                                Text(player.name).fontWeight(.semibold)
                                Text(player.uuid ?? "UUID unavailable")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    TableColumn("Ping") { player in
                        Text(player.pingMS.map { "\($0) ms" } ?? "—")
                            .font(.caption.monospacedDigit())
                    }
                    TableColumn("Address") { player in
                        Text(player.address ?? "—")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Roles") { player in
                        HStack {
                            if player.isOperator { Label("OP", systemImage: "crown.fill").labelStyle(.titleAndIcon) }
                            if player.isAllowlisted { Label("Allowlisted", systemImage: "checkmark.shield.fill").labelStyle(.titleAndIcon) }
                        }
                        .font(.caption)
                    }
                }
                .contextMenu(forSelectionType: MCPlayer.ID.self) { selected in
                    if let player = firstPlayer(in: selected) {
                        Button("Copy UUID") { copy(player.uuid ?? player.id) }
                        Button("Kick") { runtime.kick(player, reason: kickReason) }
                        Button("Send Message") { runtime.sendMessage(to: player, message: messageText.isEmpty ? "Hello from Purpur Manager" : messageText) }
                        Divider()
                        Button("Make Operator") { runtime.setOperator(player, enabled: true) }
                        Button("Remove Operator") { runtime.setOperator(player, enabled: false) }
                        Button("Add to Allowlist") { runtime.setAllowlist(player, enabled: true) }
                        Button("Remove from Allowlist") { runtime.setAllowlist(player, enabled: false) }
                        Divider()
                        Button("Ban", role: .destructive) { runtime.ban(player) }
                    }
                } primaryAction: { selected in
                    if let player = firstPlayer(in: selected) { copy(player.uuid ?? player.id) }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            SectionHeader(title: "Player Management", subtitle: "Live player list, moderation, allowlist, bans and operator actions.", symbolName: "person.2.fill")
            Spacer()
            TextField("Search players or UUIDs", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            Menu("Quick Actions", systemImage: "bolt.fill") {
                TextField("Message", text: $messageText)
                TextField("Kick reason", text: $kickReason)
                Divider()
                Button("Message Selected") { selectedPlayers.forEach { runtime.sendMessage(to: $0, message: messageText) } }
                Button("Kick Selected") { selectedPlayers.forEach { runtime.kick($0, reason: kickReason) } }
                Button("Allowlist Selected") { selectedPlayers.forEach { runtime.setAllowlist($0, enabled: true) } }
                Button("Ban Selected", role: .destructive) { selectedPlayers.forEach { runtime.ban($0) } }
            }
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await runtime.refreshSnapshot() } }
        }
        .padding(24)
    }

    private var selectedPlayers: [MCPlayer] {
        runtime.players.filter { selection.contains($0.id) }
    }

    private func firstPlayer(in selected: Set<MCPlayer.ID>) -> MCPlayer? {
        runtime.players.first { selected.contains($0.id) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

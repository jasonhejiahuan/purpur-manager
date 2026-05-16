import SwiftUI

struct ServerSettingsView: View {
    let runtime: ServerRuntime

    var body: some View {
        @Bindable var runtime = runtime
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "Server Settings", subtitle: "Live dynamic config updates with validation, history, reset and undo.", symbolName: "slider.horizontal.3")

                VStack(alignment: .leading, spacing: 18) {
                    GroupBox("World") {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
                            settingSlider("view-distance", title: "View Distance", value: $runtime.settingsDraft.viewDistance, range: 2...32)
                            settingSlider("simulation-distance", title: "Simulation Distance", value: $runtime.settingsDraft.simulationDistance, range: 2...32)
                            settingSlider("spawn-protection", title: "Spawn Protection", value: $runtime.settingsDraft.spawnProtection, range: 0...64)
                        }
                    }
                    GroupBox("Players") {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
                            settingSlider("max-players", title: "Max Players", value: $runtime.settingsDraft.maxPlayers, range: 1...500)
                            settingSlider("player-idle-timeout", title: "Idle Timeout", value: $runtime.settingsDraft.playerIdleTimeout, range: 0...120)
                            GridRow {
                                Text("MOTD")
                                TextField("MOTD", text: $runtime.settingsDraft.motd)
                                    .onSubmit { runtime.updateSetting(key: "motd", value: .string(runtime.settingsDraft.motd)) }
                                Button("Apply") { runtime.updateSetting(key: "motd", value: .string(runtime.settingsDraft.motd)) }
                            }
                        }
                    }
                    GroupBox("Gameplay") {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) {
                            pickerRow("difficulty", title: "Difficulty", selection: $runtime.settingsDraft.difficulty, values: ["peaceful", "easy", "normal", "hard"])
                            pickerRow("gamemode", title: "Gamemode", selection: $runtime.settingsDraft.gamemode, values: ["survival", "creative", "adventure", "spectator"])
                            toggleRow("autosave", title: "Autosave", isOn: $runtime.settingsDraft.autosave)
                            toggleRow("allow-flight", title: "Allow Flight", isOn: $runtime.settingsDraft.allowFlight)
                            toggleRow("hide-online-players", title: "Hide Online Players", isOn: $runtime.settingsDraft.hideOnlinePlayers)
                            toggleRow("enforce-allowlist", title: "Enforce Allowlist", isOn: $runtime.settingsDraft.enforceAllowlist)
                        }
                    }
                }
                .padding(18)
                .glassCard(cornerRadius: 24)

                HStack {
                    Button("Undo Last Change", systemImage: "arrow.uturn.backward") { runtime.undoLastSettingChange() }
                        .disabled(runtime.settingHistory.isEmpty)
                    Spacer()
                    Text("\(runtime.settingHistory.count) changes in history")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !runtime.settingHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Change History").font(.headline)
                        ForEach(runtime.settingHistory.prefix(12)) { change in
                            HStack {
                                Text(change.key).font(.caption.monospaced()).frame(width: 180, alignment: .leading)
                                Text(change.oldValue?.stableDescription ?? "—")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                Text(change.newValue.stableDescription)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(change.date, style: .time).foregroundStyle(.tertiary)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(18)
                    .glassCard(cornerRadius: 20)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func settingSlider(_ key: String, title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        GridRow {
            Text(title)
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            Text("\(value.wrappedValue)")
                .font(.caption.monospacedDigit())
                .frame(width: 46, alignment: .trailing)
            Button("Apply") { runtime.updateSetting(key: key, value: .number(Double(value.wrappedValue))) }
            Button("Reset") { runtime.resetSettingToDefault(key) }
        }
    }

    @ViewBuilder
    private func toggleRow(_ key: String, title: String, isOn: Binding<Bool>) -> some View {
        GridRow {
            Text(title)
            Toggle("", isOn: isOn)
                .onChange(of: isOn.wrappedValue) { _, newValue in runtime.updateSetting(key: key, value: .bool(newValue)) }
            Text(isOn.wrappedValue ? "Enabled" : "Disabled").foregroundStyle(.secondary)
            Button("Reset") { runtime.resetSettingToDefault(key) }
        }
    }

    @ViewBuilder
    private func pickerRow(_ key: String, title: String, selection: Binding<String>, values: [String]) -> some View {
        GridRow {
            Text(title)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: selection.wrappedValue) { _, newValue in runtime.updateSetting(key: key, value: .string(newValue)) }
            Button("Reset") { runtime.resetSettingToDefault(key) }
        }
    }
}

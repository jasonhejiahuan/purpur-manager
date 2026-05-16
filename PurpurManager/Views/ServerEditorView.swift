import SwiftUI

enum ServerEditorMode: Identifiable {
    case add
    case edit(ServerProfile)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let profile): return profile.id.uuidString
        }
    }
}

struct ServerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    var mode: ServerEditorMode

    @State private var profile: ServerProfile
    @State private var apiKey = ""
    @State private var validationMessage: String?

    init(mode: ServerEditorMode) {
        self.mode = mode
        switch mode {
        case .add:
            _profile = State(initialValue: ServerProfile(nickname: "", host: "127.0.0.1", port: 7777, usesTLS: false, autoReconnect: true, autoConnectOnLaunch: false, notifications: .default, groupName: "Default"))
        case .edit(let profile):
            _profile = State(initialValue: profile)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: title, subtitle: "Configure a native WebSocket JSON-RPC connection.", symbolName: "server.rack")

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Endpoint") {
                        VStack(spacing: 12) {
                            textFieldRow("Nickname", text: $profile.nickname, prompt: "Survival")
                            textFieldRow("Host", text: $profile.host, prompt: "127.0.0.1")
                            portRow
                            toggleRow("TLS", title: "Use TLS (wss://)", isOn: $profile.usesTLS)
                            noteRow("Endpoint", value: profile.endpoint)
                        }
                        .padding(.top, 4)
                    }

                    GroupBox("Security") {
                        VStack(spacing: 12) {
                            secureFieldRow("API key", text: $apiKey, prompt: modeIsEdit ? "Leave blank to keep existing API key" : "Required")
                            noteRow("Storage", value: "API keys are stored in macOS Keychain and are never written to the server config file.")
                        }
                        .padding(.top, 4)
                    }

                    GroupBox("Behavior") {
                        VStack(spacing: 12) {
                            textFieldRow("Group", text: $profile.groupName, prompt: "Default")
                            toggleRow("Reconnect", title: "Auto reconnect", isOn: $profile.autoReconnect)
                            toggleRow("Startup", title: "Auto connect on launch", isOn: $profile.autoConnectOnLaunch)
                        }
                        .padding(.top, 4)
                    }

                    GroupBox("Notifications") {
                        LazyVGrid(columns: notificationColumns, alignment: .leading, spacing: 10) {
                            Toggle("Player joined", isOn: $profile.notifications.playerJoined)
                            Toggle("Player left", isOn: $profile.notifications.playerLeft)
                            Toggle("Server online", isOn: $profile.notifications.serverOnline)
                            Toggle("Server offline / lost", isOn: $profile.notifications.connectionLost)
                            Toggle("Autosave complete", isOn: $profile.notifications.autosaveComplete)
                            Toggle("High latency", isOn: $profile.notifications.highLatency)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let validationMessage {
                InlineErrorView(message: validationMessage)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(modeIsEdit ? "Save" : "Add Server") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 640, height: 720)
    }

    private var modeIsEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var title: String { modeIsEdit ? "Edit Server" : "Add Server" }

    private var notificationColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 180), spacing: 18),
            GridItem(.flexible(minimum: 180), spacing: 18)
        ]
    }

    private var portRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            fieldLabel("Port")
            TextField("7777", value: $profile.port, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            Stepper("", value: $profile.port, in: 1...65535)
                .labelsHidden()
            Spacer(minLength: 0)
        }
    }

    private func textFieldRow(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            fieldLabel(label)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }

    private func secureFieldRow(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            fieldLabel(label)
            SecureField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }

    private func toggleRow(_ label: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            fieldLabel(label)
            Toggle(title, isOn: isOn)
            Spacer(minLength: 0)
        }
    }

    private func noteRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            fieldLabel(label)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 96, alignment: .trailing)
    }

    private func save() {
        guard !profile.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "Host is required."
            return
        }
        guard modeIsEdit || !apiKey.isEmpty else {
            validationMessage = "API key is required for new servers."
            return
        }
        switch mode {
        case .add:
            appModel.addServer(profile, apiKey: apiKey)
        case .edit:
            appModel.updateServer(profile, apiKey: apiKey.isEmpty ? nil : apiKey)
        }
        dismiss()
    }
}

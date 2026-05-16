import SwiftUI

struct SystemMessageView: View {
    let runtime: ServerRuntime
    @State private var message = "Hello from Purpur Manager"
    @State private var overlay = false
    @State private var selectedPreset = "Welcome"

    private let presets: [String: String] = [
        "Welcome": "Welcome to the server!",
        "Restart Soon": "Server restart in 5 minutes. Please find a safe place.",
        "Save Complete": "World save completed successfully.",
        "Maintenance": "Maintenance window is starting soon."
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: "System Messages", subtitle: "Broadcast JSON chat components using the official minecraft:server/system_message RPC format.", symbolName: "megaphone.fill")

                VStack(alignment: .leading, spacing: 16) {
                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(presets.keys.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: selectedPreset) { _, newValue in message = presets[newValue] ?? message }

                    TextEditor(text: $message)
                        .font(.system(.body, design: .rounded))
                        .frame(minHeight: 160)
                        .padding(10)
                        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Toggle("Show as action bar overlay", isOn: $overlay)
                    HStack {
                        Button("Bold Helper") { wrap(prefix: "§l", suffix: "§r") }
                        Button("Gold Helper") { wrap(prefix: "§6", suffix: "§r") }
                        Button("Red Helper") { wrap(prefix: "§c", suffix: "§r") }
                        Spacer()
                        Button("Broadcast", systemImage: "paperplane.fill") { runtime.broadcastSystemMessage(message, overlay: overlay) }
                            .buttonStyle(.borderedProminent)
                            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(20)
                .glassCard(cornerRadius: 24)

                GroupBox("Request Preview") {
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
            .padding(24)
        }
    }

    private var preview: String {
        let request = RPCRequest(id: .int(1), method: "minecraft:server/system_message", params: .object([
            "overlay": .bool(overlay),
            "message": .object(["literal": .string(message)])
        ]))
        guard let data = try? JSONEncoder.pretty.encode(request), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    private func wrap(prefix: String, suffix: String) {
        message = prefix + message + suffix
    }
}

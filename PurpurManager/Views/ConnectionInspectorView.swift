import SwiftUI

struct ConnectionInspectorView: View {
    let runtime: ServerRuntime
    @State private var frameSearch = ""

    private var filteredFrames: [WebSocketFrameRecord] {
        guard !frameSearch.isEmpty else { return runtime.frames }
        return runtime.frames.filter { $0.payload.localizedCaseInsensitiveContains(frameSearch) || ($0.method?.localizedCaseInsensitiveContains(frameSearch) ?? false) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionHeader(title: "WebSocket Inspector", subtitle: "Connection health, frame history, reconnect diagnostics and cached schemas.", symbolName: "waveform.path.ecg.rectangle.fill")
                Spacer()
                TextField("Search frames", text: $frameSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Button("Ping", systemImage: "dot.radiowaves.left.and.right") { Task { await runtime.pingNow() } }
                Button("Reconnect", systemImage: "arrow.clockwise") { runtime.reconnectNow() }
            }
            .padding(24)
            Divider().opacity(0.35)
            HSplitView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("Connection") {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                            infoRow("Endpoint", runtime.profile.endpoint)
                            infoRow("State", runtime.state.label)
                            infoRow("Ping", runtime.pingMS.map { "\(Int($0)) ms" } ?? "—")
                            infoRow("Reconnect attempts", "\(runtime.reconnectAttempts)")
                            infoRow("Capabilities", "\(runtime.methods.count) methods")
                        }
                    }
                    GroupBox("Connection Logs") {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(runtime.connectionLogs.prefix(80)) { event in
                                    HStack(alignment: .top) {
                                        Image(systemName: event.kind.symbolName).foregroundStyle(event.kind.tint)
                                        VStack(alignment: .leading) {
                                            Text(event.title).font(.caption.weight(.semibold))
                                            Text(event.message).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(event.date, style: .time).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(18)
                .frame(minWidth: 320)

                Table(filteredFrames) {
                    TableColumn("Time") { frame in Text(frame.date, style: .time).font(.caption.monospacedDigit()) }
                    TableColumn("Dir") { frame in Text(frame.direction.rawValue).foregroundStyle(frame.direction == .inbound ? .blue : .green) }
                    TableColumn("Method") { frame in Text(frame.method ?? "—").font(.caption.monospaced()) }
                    TableColumn("ID") { frame in Text(frame.rpcID ?? "—").font(.caption.monospaced()) }
                    TableColumn("Payload") { frame in Text(frame.compactPayload).font(.caption.monospaced()).foregroundStyle(frame.isError ? .red : .primary) }
                }
                .frame(minWidth: 520)
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced())
        }
    }
}

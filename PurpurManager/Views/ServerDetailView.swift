import SwiftUI

struct ServerDetailView: View {
    @Environment(AppModel.self) private var appModel
    let runtime: ServerRuntime

    var body: some View {
        @Bindable var appModel = appModel
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            HStack(spacing: 0) {
                List(AppSection.allCases, selection: $appModel.selectedSection) { section in
                    Label(section.title, systemImage: section.symbolName)
                        .tag(section)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .frame(width: 190)
                Divider().opacity(0.35)
                detail
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(runtime.profile.displayName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(runtime.profile.endpoint)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            StatusBadge(state: runtime.state, text: runtime.healthSummary)
            Spacer()
            if let error = runtime.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Button("Reconnect", systemImage: "arrow.clockwise") { runtime.reconnectNow() }
            Button("Save", systemImage: "externaldrive.fill") { runtime.saveServer() }
            Button("Stop", systemImage: "power") { runtime.stopServer() }
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var detail: some View {
        switch appModel.selectedSection {
        case .dashboard: DashboardView(runtime: runtime)
        case .players: PlayerManagementView(runtime: runtime)
        case .settings: ServerSettingsView(runtime: runtime)
        case .gamerules: GameruleEditorView(runtime: runtime)
        case .console: RPCConsoleView(runtime: runtime)
        case .logs: LogViewerView(runtime: runtime)
        case .messages: SystemMessageView(runtime: runtime)
        case .inspector: ConnectionInspectorView(runtime: runtime)
        }
    }
}

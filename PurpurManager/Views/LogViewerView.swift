import SwiftUI

struct LogViewerView: View {
    let runtime: ServerRuntime
    @State private var searchText = ""
    @State private var regexMode = false
    @State private var paused = false
    @State private var selectedSeverity: ActivityEvent.Kind?

    private var logs: [ActivityEvent] {
        let source = paused ? Array(runtime.serverLogs) : runtime.serverLogs
        return source.filter { event in
            let severityMatches = selectedSeverity == nil || event.kind == selectedSeverity
            let textMatches: Bool
            if searchText.isEmpty {
                textMatches = true
            } else if regexMode, let regex = try? Regex(searchText) {
                textMatches = event.message.contains(regex) || event.title.contains(regex)
            } else {
                textMatches = event.message.localizedCaseInsensitiveContains(searchText) || event.title.localizedCaseInsensitiveContains(searchText)
            }
            return severityMatches && textMatches
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SectionHeader(title: "Log Viewer", subtitle: "Live log stream with ANSI cleanup, severity coloring, regex filter and export.", symbolName: "doc.text.magnifyingglass")
                Spacer()
                Toggle("Regex", isOn: $regexMode)
                Toggle("Pause", isOn: $paused)
                TextField("Search logs", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Menu("Severity") {
                    Button("All") { selectedSeverity = nil }
                    Button("Info") { selectedSeverity = .log }
                    Button("Warning") { selectedSeverity = .warning }
                    Button("Error") { selectedSeverity = .error }
                }
                Button("Export", systemImage: "square.and.arrow.up") { runtime.exportLogs() }
            }
            .padding(24)
            Divider().opacity(0.35)
            if logs.isEmpty {
                ContentUnavailableView("No Logs", systemImage: "doc.text", description: Text("Log notification frames will appear here when the server publishes them."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(logs) { log in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(log.date, style: .time)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 72, alignment: .leading)
                                    Text(log.title)
                                        .font(.caption.monospaced().weight(.bold))
                                        .foregroundStyle(log.kind.tint)
                                        .frame(width: 56, alignment: .leading)
                                    Text(log.message)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .id(log.id)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                                .background(log.kind.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: runtime.serverLogs.first?.id) { _, newValue in
                        guard !paused, let newValue else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newValue, anchor: .top) }
                    }
                }
            }
        }
    }
}

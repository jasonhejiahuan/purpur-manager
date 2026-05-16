import Charts
import SwiftUI

struct DashboardView: View {
    @Environment(AppPreferences.self) private var preferences
    let runtime: ServerRuntime

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: "Realtime Dashboard", subtitle: "Live status, player activity, JVM health and latency for \(runtime.profile.displayName).", symbolName: "gauge.with.dots.needle.67percent")

                LazyVGrid(columns: columns, spacing: 16) {
                    MetricCard(title: "Status", value: runtime.state.label, subtitle: runtime.lastConnectedAt.map { "Connected \($0.formatted(date: .omitted, time: .shortened))" }, symbolName: runtime.state.symbolName, tint: runtime.state.tint)
                    MetricCard(title: "TPS Estimate", value: runtime.status.tps.map { String(format: "%.2f", $0) } ?? "—", subtitle: "20.00 ideal", symbolName: "speedometer", tint: .green)
                    MetricCard(title: "Players", value: playerCountText, subtitle: runtime.status.maxPlayers.map { "Max \($0)" }, symbolName: "person.2.fill", tint: .blue)
                    MetricCard(title: "Uptime", value: runtime.formattedUptime, subtitle: runtime.status.version, symbolName: "clock.arrow.circlepath", tint: .purple)
                    MetricCard(title: "View Distance", value: runtime.status.viewDistance.map(String.init) ?? "—", subtitle: "Simulation \(runtime.status.simulationDistance.map(String.init) ?? "—")", symbolName: "eye.fill", tint: .mint)
                    MetricCard(title: "Autosave", value: runtime.status.autosaveEnabled.map { $0 ? "On" : "Off" } ?? "—", subtitle: runtime.status.jvmName, symbolName: "externaldrive.fill", tint: .indigo)
                }

                HStack(alignment: .top, spacing: 16) {
                    if preferences.showMemoryWidget {
                        ChartCard(title: "Memory", subtitle: memorySubtitle, symbolName: "memorychip.fill", samples: runtime.memorySamples, color: .purple, unit: "MB")
                    }
                    if preferences.showPlayerWidget {
                        ChartCard(title: "Players", subtitle: "Online players over time", symbolName: "person.2.wave.2.fill", samples: runtime.playerSamples, color: .blue, unit: "")
                    }
                    if preferences.showLatencyWidget {
                        ChartCard(title: "Latency", subtitle: runtime.pingMS.map { "Current \(Int($0)) ms" } ?? "WebSocket ping", symbolName: "waveform.path.ecg", samples: runtime.latencySamples, color: .green, unit: "ms")
                    }
                }
                .frame(minHeight: 280)

                ActivityFeedView(events: runtime.activity)
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
    }

    private var playerCountText: String {
        if let count = runtime.status.playerCount { return "\(count)" }
        return "\(runtime.players.count)"
    }

    private var memorySubtitle: String {
        let used = runtime.status.memoryUsedMB.map { "\(Int($0)) MB" } ?? "—"
        let max = runtime.status.memoryMaxMB.map { "\(Int($0)) MB" } ?? "—"
        return "\(used) of \(max)"
    }
}

private struct ChartCard: View {
    var title: String
    var subtitle: String
    var symbolName: String
    var samples: [MetricSample]
    var color: Color
    var unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: symbolName)
                    .font(.headline)
                Spacer()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if samples.isEmpty {
                ContentUnavailableView("Waiting for samples", systemImage: "chart.xyaxis.line", description: Text("Data appears after the first status heartbeat."))
                    .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                Chart(samples) { sample in
                    LineMark(x: .value("Time", sample.date), y: .value(title, sample.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(color.gradient)
                    AreaMark(x: .value("Time", sample.date), y: .value(title, sample.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.32), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                }
                .chartYAxisLabel(unit)
                .chartXAxis(.hidden)
                .frame(height: 190)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard(cornerRadius: 24)
    }
}

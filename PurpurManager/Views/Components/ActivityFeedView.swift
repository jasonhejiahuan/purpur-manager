import SwiftUI

struct ActivityFeedView: View {
    var events: [ActivityEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Activity", systemImage: "bolt.horizontal.circle.fill")
                    .font(.headline)
                Spacer()
                Text("\(events.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if events.isEmpty {
                ContentUnavailableView("No activity yet", systemImage: "dot.radiowaves.left.and.right", description: Text("Events from JSON-RPC notifications will appear here."))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(events.prefix(18)) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: event.kind.symbolName)
                                .foregroundStyle(event.kind.tint)
                                .frame(width: 28, height: 28)
                                .background(event.kind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(event.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(event.date, style: .time)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 24)
    }
}

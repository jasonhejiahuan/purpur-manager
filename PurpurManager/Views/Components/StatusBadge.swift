import SwiftUI

struct StatusBadge: View {
    var state: ConnectionState
    var text: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.symbolName)
                .symbolEffect(.pulse, isActive: state == .connecting || state == .reconnecting)
            Text(text ?? state.label)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .foregroundStyle(state.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(state.tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(state.tint.opacity(0.25)))
    }
}

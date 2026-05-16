import SwiftUI

struct SectionHeader: View {
    var title: String
    var subtitle: String?
    var symbolName: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

import SwiftUI

struct AppBackground: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        ZStack {
            LinearGradient(colors: [preferences.accent.color.opacity(0.24), .black.opacity(0.08), .blue.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            RadialGradient(colors: [preferences.accent.color.opacity(0.28), .clear], center: .topTrailing, startRadius: 40, endRadius: 520)
                .ignoresSafeArea()
            RadialGradient(colors: [.cyan.opacity(0.12), .clear], center: .bottomLeading, startRadius: 20, endRadius: 480)
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func dashboardTitle() -> some View {
        font(.system(.largeTitle, design: .rounded, weight: .bold))
    }
}

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 26, x: 0, y: 18)
    }
}

struct FrostedToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}

struct HoverScale: ViewModifier {
    @State private var hovering = false
    var enabled = true

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && enabled ? 1.015 : 1)
            .animation(.snappy(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
    }
}

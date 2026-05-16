import Foundation
import SwiftUI
import Observation

enum ThemePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case dark
    case light

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

enum AccentPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case purple
    case blue
    case mint
    case orange
    case pink
    case green

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .purple: return .purple
        case .blue: return .blue
        case .mint: return .mint
        case .orange: return .orange
        case .pink: return .pink
        case .green: return .green
        }
    }
}

@MainActor
@Observable
final class AppPreferences {
    var accent: AccentPreference { didSet { save() } }
    var compactMode: Bool { didSet { save() } }
    var sidebarWidth: Double { didSet { save() } }
    var notifyInForeground: Bool { didSet { save() } }
    var globalAutoReconnect: Bool { didSet { save() } }
    var refreshInterval: Double { didSet { save() } }
    var theme: ThemePreference { didSet { save() } }
    var reducedMotion: Bool { didSet { save() } }
    var fontScale: Double { didSet { save() } }
    var showMemoryWidget: Bool { didSet { save() } }
    var showPlayerWidget: Bool { didSet { save() } }
    var showLatencyWidget: Bool { didSet { save() } }
    var launchMenuBarOnly: Bool { didSet { save() } }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let key = "PurpurManager.AppPreferences.v1"

    init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Storage.self, from: data) {
            accent = decoded.accent
            compactMode = decoded.compactMode
            sidebarWidth = decoded.sidebarWidth
            notifyInForeground = decoded.notifyInForeground
            globalAutoReconnect = decoded.globalAutoReconnect
            refreshInterval = decoded.refreshInterval
            theme = decoded.theme
            reducedMotion = decoded.reducedMotion
            fontScale = decoded.fontScale
            showMemoryWidget = decoded.showMemoryWidget
            showPlayerWidget = decoded.showPlayerWidget
            showLatencyWidget = decoded.showLatencyWidget
            launchMenuBarOnly = decoded.launchMenuBarOnly
        } else {
            accent = .purple
            compactMode = false
            sidebarWidth = 260
            notifyInForeground = true
            globalAutoReconnect = true
            refreshInterval = 5
            theme = .dark
            reducedMotion = false
            fontScale = 1
            showMemoryWidget = true
            showPlayerWidget = true
            showLatencyWidget = true
            launchMenuBarOnly = false
        }
    }

    func reset() {
        accent = .purple
        compactMode = false
        sidebarWidth = 260
        notifyInForeground = true
        globalAutoReconnect = true
        refreshInterval = 5
        theme = .dark
        reducedMotion = false
        fontScale = 1
        showMemoryWidget = true
        showPlayerWidget = true
        showLatencyWidget = true
        launchMenuBarOnly = false
    }

    private func save() {
        let storage = Storage(accent: accent,
                              compactMode: compactMode,
                              sidebarWidth: sidebarWidth,
                              notifyInForeground: notifyInForeground,
                              globalAutoReconnect: globalAutoReconnect,
                              refreshInterval: refreshInterval,
                              theme: theme,
                              reducedMotion: reducedMotion,
                              fontScale: fontScale,
                              showMemoryWidget: showMemoryWidget,
                              showPlayerWidget: showPlayerWidget,
                              showLatencyWidget: showLatencyWidget,
                              launchMenuBarOnly: launchMenuBarOnly)
        if let data = try? JSONEncoder.pretty.encode(storage) {
            defaults.set(data, forKey: key)
        }
    }

    private struct Storage: Codable {
        var accent: AccentPreference
        var compactMode: Bool
        var sidebarWidth: Double
        var notifyInForeground: Bool
        var globalAutoReconnect: Bool
        var refreshInterval: Double
        var theme: ThemePreference
        var reducedMotion: Bool
        var fontScale: Double
        var showMemoryWidget: Bool
        var showPlayerWidget: Bool
        var showLatencyWidget: Bool
        var launchMenuBarOnly: Bool
    }
}

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var profiles: [ServerProfile] = []
    var selectedServerID: UUID?
    var selectedSection: AppSection = .dashboard
    var runtimes: [UUID: ServerRuntime] = [:]
    var globalError: String?

    @ObservationIgnored private let store = ServerStore()
    @ObservationIgnored private let keychain = KeychainStore.shared
    @ObservationIgnored private let schemaCache = RPCSchemaCache()
    @ObservationIgnored private let notificationService = NotificationService.shared

    init() {
        profiles = store.load()
        if profiles.isEmpty {
            profiles = [ServerProfile.sample]
            try? store.save(profiles)
        }
        rebuildRuntimes()
        selectedServerID = profiles.first?.id
    }

    var selectedProfile: ServerProfile? {
        guard let selectedServerID else { return nil }
        return profiles.first { $0.id == selectedServerID }
    }

    var selectedRuntime: ServerRuntime? {
        guard let selectedServerID else { return nil }
        return runtimes[selectedServerID]
    }

    var groupedProfiles: [(String, [ServerProfile])] {
        let groups = Dictionary(grouping: profiles) { $0.groupName.isEmpty ? "Default" : $0.groupName }
        return groups.keys.sorted().map { key in
            (key, groups[key, default: []].sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending })
        }
    }

    func runtime(for profile: ServerProfile) -> ServerRuntime {
        if let runtime = runtimes[profile.id] { return runtime }
        let runtime = ServerRuntime(profile: profile, keychain: keychain, schemaCache: schemaCache, notificationService: notificationService)
        runtimes[profile.id] = runtime
        return runtime
    }

    func addServer(_ profile: ServerProfile, apiKey: String) {
        var newProfile = profile
        newProfile.updatedAt = Date()
        profiles.append(newProfile)
        persistProfiles()
        if !apiKey.isEmpty { try? keychain.saveToken(apiKey, for: newProfile.id) }
        runtimes[newProfile.id] = ServerRuntime(profile: newProfile, keychain: keychain, schemaCache: schemaCache, notificationService: notificationService)
        selectedServerID = newProfile.id
    }

    func updateServer(_ profile: ServerProfile, apiKey: String?) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        updated.updatedAt = Date()
        profiles[index] = updated
        persistProfiles()
        if let apiKey, !apiKey.isEmpty { try? keychain.saveToken(apiKey, for: profile.id) }
        runtimes[profile.id]?.updateProfile(updated)
    }

    func removeServer(_ profile: ServerProfile) {
        runtimes[profile.id]?.disconnect(manual: true)
        runtimes.removeValue(forKey: profile.id)
        profiles.removeAll { $0.id == profile.id }
        try? keychain.deleteToken(for: profile.id)
        persistProfiles()
        selectedServerID = profiles.first?.id
    }

    func connectSelected() {
        selectedRuntime?.connect()
    }

    func disconnectSelected() {
        selectedRuntime?.disconnect(manual: true)
    }

    func connectAllAuto() {
        for profile in profiles where profile.autoConnectOnLaunch {
            runtimes[profile.id]?.connect()
        }
    }

    func connectAll() {
        for profile in profiles { runtimes[profile.id]?.connect() }
    }

    func disconnectAll() {
        for runtime in runtimes.values { runtime.disconnect(manual: true) }
    }

    func exportServers() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PurpurManager-Servers.json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do { try self.store.export(self.profiles, to: url) }
            catch { self.globalError = error.localizedDescription }
        }
    }

    func importServers() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let imported = try self.store.importProfiles(from: url)
                self.profiles.append(contentsOf: imported)
                self.persistProfiles()
                self.rebuildRuntimes()
                self.selectedServerID = imported.first?.id ?? self.selectedServerID
            } catch {
                self.globalError = error.localizedDescription
            }
        }
    }

    private func rebuildRuntimes() {
        for profile in profiles {
            let existing = runtimes[profile.id]
            if let existing {
                existing.updateProfile(profile)
            } else {
                runtimes[profile.id] = ServerRuntime(profile: profile, keychain: keychain, schemaCache: schemaCache, notificationService: notificationService)
            }
        }
        let ids = Set(profiles.map(\.id))
        for id in runtimes.keys where !ids.contains(id) {
            runtimes[id]?.disconnect(manual: true)
            runtimes.removeValue(forKey: id)
        }
    }

    private func persistProfiles() {
        do { try store.save(profiles) }
        catch { globalError = error.localizedDescription }
    }
}

enum AppSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case dashboard
    case players
    case settings
    case gamerules
    case console
    case logs
    case messages
    case inspector

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .players: return "Players"
        case .settings: return "Settings"
        case .gamerules: return "Gamerules"
        case .console: return "RPC Console"
        case .logs: return "Logs"
        case .messages: return "Messages"
        case .inspector: return "Inspector"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .players: return "person.2.fill"
        case .settings: return "slider.horizontal.3"
        case .gamerules: return "switch.2"
        case .console: return "terminal.fill"
        case .logs: return "doc.text.magnifyingglass"
        case .messages: return "megaphone.fill"
        case .inspector: return "waveform.path.ecg.rectangle.fill"
        }
    }
}

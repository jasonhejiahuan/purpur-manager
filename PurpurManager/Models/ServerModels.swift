import Foundation
import SwiftUI

enum ConnectionState: String, Codable, Hashable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case offline
    case failed

    var isActive: Bool { self == .connected || self == .connecting || self == .reconnecting }

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Online"
        case .reconnecting: return "Reconnecting"
        case .offline: return "Offline"
        case .failed: return "Failed"
        }
    }

    var symbolName: String {
        switch self {
        case .connected: return "checkmark.circle.fill"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath.circle.fill"
        case .offline: return "xmark.octagon.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .disconnected: return "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        case .offline, .failed: return .red
        case .disconnected: return .secondary
        }
    }
}

struct ServerProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var nickname: String
    var host: String
    var port: Int
    var usesTLS: Bool
    var autoReconnect: Bool
    var autoConnectOnLaunch: Bool
    var notifications: NotificationPreferences
    var groupName: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var displayName: String { nickname.isEmpty ? host : nickname }
    var endpoint: String { "\(usesTLS ? "wss" : "ws")://\(host):\(port)" }

    static let sample = ServerProfile(nickname: "Survival", host: "127.0.0.1", port: 7777, usesTLS: false, autoReconnect: true, autoConnectOnLaunch: false, notifications: .default, groupName: "Default")
}

struct NotificationPreferences: Codable, Hashable, Sendable {
    var playerJoined: Bool = true
    var playerLeft: Bool = true
    var serverOffline: Bool = true
    var serverOnline: Bool = true
    var autosaveComplete: Bool = false
    var highLatency: Bool = true
    var connectionLost: Bool = true

    static let `default` = NotificationPreferences()
}

struct ServerStatus: Codable, Hashable, Sendable {
    var started: Bool?
    var version: String?
    var jvmName: String?
    var jvmVersion: String?
    var tps: Double?
    var playerCount: Int?
    var maxPlayers: Int?
    var uptimeSeconds: TimeInterval?
    var viewDistance: Int?
    var simulationDistance: Int?
    var autosaveEnabled: Bool?
    var memoryUsedMB: Double?
    var memoryMaxMB: Double?
    var motd: String?
    var difficulty: String?
    var gamemode: String?

    static func fromJSON(_ value: JSONValue) -> ServerStatus {
        let source = value.value(for: "status") ?? value.value(for: "server") ?? value
        let playersArray = source.value(for: "players")?.arrayValue
        return ServerStatus(
            started: source.value(anyOf: ["started", "running", "online"])?.boolValue,
            version: source.value(anyOf: ["version.name", "version", "minecraftVersion", "server.version.name", "software.version"])?.stringValue,
            jvmName: source.value(anyOf: ["jvm.name", "java.name", "system.jvm.name"])?.stringValue,
            jvmVersion: source.value(anyOf: ["jvm.version", "java.version", "system.jvm.version"])?.stringValue,
            tps: source.value(anyOf: ["tps", "performance.tps", "server.tps", "ticksPerSecond"])?.doubleValue,
            playerCount: source.value(anyOf: ["players.online", "playerCount", "onlinePlayers", "players.count"])?.intValue ?? playersArray?.count,
            maxPlayers: source.value(anyOf: ["players.max", "maxPlayers", "settings.max-players", "settings.maxPlayers"])?.intValue,
            uptimeSeconds: source.value(anyOf: ["uptime", "uptimeSeconds", "server.uptime"] )?.doubleValue,
            viewDistance: source.value(anyOf: ["viewDistance", "settings.view-distance", "settings.viewDistance"])?.intValue,
            simulationDistance: source.value(anyOf: ["simulationDistance", "settings.simulation-distance", "settings.simulationDistance"])?.intValue,
            autosaveEnabled: source.value(anyOf: ["autosave", "autosaveEnabled", "settings.autosave"])?.boolValue,
            memoryUsedMB: source.value(anyOf: ["memory.usedMB", "memory.used", "jvm.memory.usedMB", "system.memory.usedMB"])?.doubleValue.map(ServerStatus.normalizeMemory),
            memoryMaxMB: source.value(anyOf: ["memory.maxMB", "memory.max", "jvm.memory.maxMB", "system.memory.maxMB"])?.doubleValue.map(ServerStatus.normalizeMemory),
            motd: source.value(anyOf: ["motd", "settings.motd"])?.stringValue,
            difficulty: source.value(anyOf: ["difficulty", "settings.difficulty"])?.stringValue,
            gamemode: source.value(anyOf: ["gamemode", "gameMode", "settings.gamemode"])?.stringValue
        )
    }

    private static func normalizeMemory(_ value: Double) -> Double {
        // Some APIs report bytes. Values above 1 GB are almost certainly bytes; convert to MiB.
        value > 1_000_000 ? value / 1_048_576 : value
    }
}

struct MCPlayer: Identifiable, Codable, Hashable, Sendable {
    var id: String { uuid ?? name }
    var name: String
    var uuid: String?
    var address: String?
    var pingMS: Int?
    var joinedAt: Date?
    var isOperator: Bool = false
    var isAllowlisted: Bool = false

    static func list(from value: JSONValue) -> [MCPlayer] {
        let array = value.value(anyOf: ["players", "result.players", "online", "result.online"])?.arrayValue ?? value.arrayValue ?? []
        return array.compactMap { item in
            if let name = item.stringValue {
                return MCPlayer(name: name, uuid: nil)
            }
            guard let object = item.objectValue else { return nil }
            let playerObject = object["player"]?.objectValue
            let name = object["name"]?.stringValue
                ?? object["username"]?.stringValue
                ?? object["displayName"]?.stringValue
                ?? playerObject?["name"]?.stringValue
            guard let name else { return nil }
            return MCPlayer(name: name,
                            uuid: object["uuid"]?.stringValue ?? object["id"]?.stringValue ?? playerObject?["id"]?.stringValue ?? playerObject?["uuid"]?.stringValue,
                            address: object["address"]?.stringValue ?? object["ip"]?.stringValue,
                            pingMS: object["ping"]?.intValue ?? object["latency"]?.intValue,
                            joinedAt: nil,
                            isOperator: object["operator"]?.boolValue ?? object["op"]?.boolValue ?? false,
                            isAllowlisted: object["allowlisted"]?.boolValue ?? object["whitelisted"]?.boolValue ?? false)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum GameruleValueType: String, Codable, CaseIterable, Sendable {
    case boolean
    case integer
    case string

    var label: String { rawValue.capitalized }
}

struct GameruleEntry: Identifiable, Codable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var value: JSONValue
    var type: GameruleValueType
    var category: String
    var favorite: Bool = false
    var updatedAt: Date = Date()

    var boolValue: Bool { value.boolValue ?? false }
    var intValue: Int { value.intValue ?? 0 }
    var stringValue: String { value.stringValue ?? value.stableDescription }

    static func list(from value: JSONValue, favorites: Set<String> = []) -> [GameruleEntry] {
        let source = value.value(anyOf: ["gamerules", "gameRules", "result.gamerules", "result.gameRules"]) ?? value
        if let array = source.arrayValue {
            return array.compactMap { item in
                guard let object = item.objectValue,
                      let key = object["key"]?.stringValue,
                      let ruleValue = object["value"] else { return nil }
                let declaredType = object["type"]?.stringValue
                let type: GameruleValueType
                if declaredType == "boolean" { type = .boolean }
                else if declaredType == "integer" { type = .integer }
                else if case .bool = ruleValue { type = .boolean }
                else if case .number = ruleValue { type = .integer }
                else { type = .string }
                return GameruleEntry(name: key, value: ruleValue, type: type, category: Self.category(for: key), favorite: favorites.contains(key))
            }.sorted {
                if $0.favorite != $1.favorite { return $0.favorite && !$1.favorite }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        guard let object = source.objectValue else { return [] }
        return object.map { key, json in
            let type: GameruleValueType
            if json.boolValue != nil, case .bool = json { type = .boolean }
            else if json.intValue != nil, case .number = json { type = .integer }
            else if let string = json.stringValue, ["true", "false"].contains(string.lowercased()) { type = .boolean }
            else if json.intValue != nil { type = .integer }
            else { type = .string }
            return GameruleEntry(name: key, value: json, type: type, category: Self.category(for: key), favorite: favorites.contains(key))
        }.sorted {
            if $0.favorite != $1.favorite { return $0.favorite && !$1.favorite }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func category(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("mob") || lower.contains("spawn") { return "Mobs & Spawning" }
        if lower.contains("fire") || lower.contains("weather") || lower.contains("daylight") { return "World" }
        if lower.contains("player") || lower.contains("death") || lower.contains("keep") { return "Players" }
        if lower.contains("command") || lower.contains("admin") { return "Administration" }
        return "General"
    }
}

struct ServerSettingsDraft: Codable, Hashable, Sendable {
    var viewDistance: Int = 10
    var simulationDistance: Int = 10
    var maxPlayers: Int = 20
    var motd: String = "A Minecraft Server"
    var difficulty: String = "normal"
    var gamemode: String = "survival"
    var autosave: Bool = true
    var allowFlight: Bool = false
    var playerIdleTimeout: Int = 0
    var spawnProtection: Int = 16
    var hideOnlinePlayers: Bool = false
    var enforceAllowlist: Bool = false

    mutating func merge(status: ServerStatus) {
        viewDistance = status.viewDistance ?? viewDistance
        simulationDistance = status.simulationDistance ?? simulationDistance
        maxPlayers = status.maxPlayers ?? maxPlayers
        motd = status.motd ?? motd
        difficulty = status.difficulty ?? difficulty
        gamemode = status.gamemode ?? gamemode
        autosave = status.autosaveEnabled ?? autosave
    }
}

struct ActivityEvent: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case connection
        case player
        case save
        case gamerule
        case operatorChange
        case settings
        case rpc
        case log
        case warning
        case error

        var symbolName: String {
            switch self {
            case .connection: return "antenna.radiowaves.left.and.right"
            case .player: return "person.2.fill"
            case .save: return "externaldrive.fill"
            case .gamerule: return "switch.2"
            case .operatorChange: return "crown.fill"
            case .settings: return "slider.horizontal.3"
            case .rpc: return "curlybraces.square.fill"
            case .log: return "doc.text.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .connection: return .cyan
            case .player: return .green
            case .save: return .indigo
            case .gamerule: return .purple
            case .operatorChange: return .orange
            case .settings: return .blue
            case .rpc: return .mint
            case .log: return .secondary
            case .warning: return .yellow
            case .error: return .red
            }
        }
    }

    var id = UUID()
    var date = Date()
    var kind: Kind
    var title: String
    var message: String
}

struct MetricSample: Identifiable, Hashable, Sendable {
    var id = UUID()
    var date = Date()
    var value: Double
}

struct SettingChange: Identifiable, Hashable, Sendable {
    var id = UUID()
    var date = Date()
    var key: String
    var oldValue: JSONValue?
    var newValue: JSONValue
}

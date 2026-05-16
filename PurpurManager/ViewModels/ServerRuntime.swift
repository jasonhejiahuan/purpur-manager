import AppKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class ServerRuntime {
    var profile: ServerProfile
    var state: ConnectionState = .disconnected
    var status = ServerStatus()
    var players: [MCPlayer] = []
    var gamerules: [GameruleEntry] = []
    var methods: [RPCMethodDescriptor] = []
    var activity: [ActivityEvent] = []
    var frames: [WebSocketFrameRecord] = []
    var connectionLogs: [ActivityEvent] = []
    var serverLogs: [ActivityEvent] = []
    var memorySamples: [MetricSample] = []
    var playerSamples: [MetricSample] = []
    var latencySamples: [MetricSample] = []
    var pingMS: Double?
    var lastError: String?
    var lastConnectedAt: Date?
    var reconnectAttempts: Int = 0
    var settingsDraft = ServerSettingsDraft()
    var settingHistory: [SettingChange] = []
    var favoriteGamerules: Set<String> = []
    var rpcHistory: [String] = []
    var savedSnippets: [String] = []
    var isBootstrapped = false

    @ObservationIgnored private let client = WebSocketRPCClient()
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let schemaCache: RPCSchemaCache
    @ObservationIgnored private let notificationService: NotificationService
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var manualDisconnect = false
    @ObservationIgnored private let logger = Logger(subsystem: "PurpurManager", category: "ServerRuntime")

    init(profile: ServerProfile, keychain: KeychainStore, schemaCache: RPCSchemaCache, notificationService: NotificationService) {
        self.profile = profile
        self.keychain = keychain
        self.schemaCache = schemaCache
        self.notificationService = notificationService
        Task { [weak self] in
            guard let self else { return }
            self.methods = await schemaCache.load(for: profile.id)
        }
    }

    deinit {
        eventTask?.cancel()
        pollTask?.cancel()
        reconnectTask?.cancel()
    }

    var healthSummary: String {
        if let pingMS { return "\(Int(pingMS)) ms" }
        return state.label
    }

    var formattedUptime: String {
        guard let seconds = status.uptimeSeconds else { return "—" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "—"
    }

    func updateProfile(_ profile: ServerProfile) {
        self.profile = profile
    }

    func connect() {
        manualDisconnect = false
        reconnectTask?.cancel()
        eventTask?.cancel()
        lastError = nil
        appendLog(kind: .connection, title: "Connecting", message: profile.endpoint)
        eventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.client.makeEventStream()
            for await event in stream {
                await self.handle(event)
            }
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let token = try self.keychain.token(for: self.profile.id)
                try await self.client.connect(profile: self.profile, token: token)
                await self.bootstrap()
            } catch {
                await self.connectionFailed(error)
            }
        }
    }

    func disconnect(manual: Bool) {
        manualDisconnect = manual
        reconnectTask?.cancel()
        pollTask?.cancel()
        Task { [weak self] in
            await self?.client.disconnect()
        }
        state = .disconnected
        appendLog(kind: .connection, title: "Disconnected", message: manual ? "Manual disconnect" : "Connection closed")
    }

    func reconnectNow() {
        disconnect(manual: false)
        connect()
    }

    func refreshGamerules() async {
        await refreshSnapshot()
        await loadGamerules()
    }

    func refreshSnapshot() async {
        guard state == .connected else { return }
        do {
            let statusValue = try await call("minecraft:server/status")
            applyStatus(statusValue)
        } catch {
            appendLog(kind: .warning, title: "Status refresh failed", message: error.localizedDescription)
        }
        do {
            let playerValue = try await call("minecraft:players")
            players = MCPlayer.list(from: playerValue)
            appendPlayerSample()
        } catch {
            // Some servers expose players through server/status only; this is non-fatal.
        }
        await pingNow()
    }

    func pingNow() async {
        guard state == .connected else { return }
        do {
            let latency = try await client.ping()
            pingMS = latency * 1_000
            appendLatencySample(latency * 1_000)
            if latency > 1.5, profile.notifications.highLatency {
                notificationService.notify(title: "High latency", body: "\(profile.displayName) ping is \(Int(latency * 1_000)) ms")
            }
        } catch {
            appendLog(kind: .warning, title: "Ping failed", message: error.localizedDescription)
        }
    }

    @discardableResult
    func call(_ method: String, params: JSONValue? = nil) async throws -> JSONValue {
        let result = try await client.call(method: method, params: params)
        return result
    }

    func sendRaw(_ text: String) async throws {
        rpcHistory.insert(text, at: 0)
        rpcHistory = Array(rpcHistory.prefix(80))
        try await client.sendRaw(text)
    }

    func kick(_ player: MCPlayer, reason: String = "Kicked by Purpur Manager") {
        let params: JSONValue = .object([
            "kick": .array([
                .object([
                    "player": playerJSON(player),
                    "message": .object(["literal": .string(reason)])
                ])
            ])
        ])
        Task { await performQuickRPC(methods: ["minecraft:players/kick", "minecraft:player/kick"], params: params, title: "Kick \(player.name)") }
    }

    func sendMessage(to player: MCPlayer, message: String) {
        let params: JSONValue = .object(["player": .string(player.name), "message": .object(["literal": .string(message)])])
        Task { await performQuickRPC(methods: ["minecraft:players/message", "minecraft:player/message"], params: params, title: "Message \(player.name)") }
    }

    func setOperator(_ player: MCPlayer, enabled: Bool) {
        let method = enabled ? "minecraft:operators/add" : "minecraft:operators/remove"
        let params: JSONValue = enabled
            ? .object(["add": .array([.object(["player": playerJSON(player), "permissionLevel": .number(4), "bypassesPlayerLimit": .bool(false)])])])
            : .object(["remove": .array([playerJSON(player)])])
        Task { await performQuickRPC(methods: [method], params: params, title: enabled ? "Add operator" : "Remove operator") }
    }

    func setAllowlist(_ player: MCPlayer, enabled: Bool) {
        let method = enabled ? "minecraft:allowlist/add" : "minecraft:allowlist/remove"
        let key = enabled ? "add" : "remove"
        let params: JSONValue = .object([key: .array([playerJSON(player)])])
        Task { await performQuickRPC(methods: [method], params: params, title: enabled ? "Allowlist player" : "Remove from allowlist") }
    }

    func ban(_ player: MCPlayer, reason: String = "Banned by Purpur Manager") {
        let params: JSONValue = .object([
            "add": .array([
                .object(["player": playerJSON(player), "reason": .string(reason), "source": .string("Purpur Manager")])
            ])
        ])
        Task { await performQuickRPC(methods: ["minecraft:bans/add", "minecraft:players/ban"], params: params, title: "Ban \(player.name)") }
    }

    func updateSetting(key: String, value: JSONValue) {
        let oldValue = settingsValue(for: key)
        settingHistory.insert(SettingChange(key: key, oldValue: oldValue, newValue: value), at: 0)
        settingHistory = Array(settingHistory.prefix(60))
        guard let request = settingRPC(for: key, value: value) else {
            appendLog(kind: .warning, title: "Unsupported setting", message: key)
            return
        }
        Task { await performQuickRPC(methods: [request.method], params: request.params, title: "Update \(key)") }
    }

    func undoLastSettingChange() {
        guard let change = settingHistory.first, let old = change.oldValue else { return }
        settingHistory.removeFirst()
        updateSetting(key: change.key, value: old)
    }

    func resetSettingToDefault(_ key: String) {
        guard let value = defaultSettingValue(for: key) else { return }
        updateSetting(key: key, value: value)
    }

    func updateGamerule(_ rule: GameruleEntry, value: JSONValue) {
        let params: JSONValue = .object([
            "gamerule": .object([
                "key": .string(rule.name),
                "value": value
            ])
        ])
        Task { await performQuickRPC(methods: ["minecraft:gamerules/update", "minecraft:gamerules/set", "minecraft:gamerule/set"], params: params, title: "Update \(rule.name)") }
        if let index = gamerules.firstIndex(where: { $0.id == rule.id }) {
            gamerules[index].value = value
            gamerules[index].updatedAt = Date()
        }
    }

    func toggleFavorite(_ rule: GameruleEntry) {
        if favoriteGamerules.contains(rule.name) { favoriteGamerules.remove(rule.name) }
        else { favoriteGamerules.insert(rule.name) }
        gamerules = gamerules.map { entry in
            var copy = entry
            copy.favorite = favoriteGamerules.contains(entry.name)
            return copy
        }.sorted { $0.favorite != $1.favorite ? $0.favorite : $0.name < $1.name }
    }

    func exportGamerules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(profile.displayName)-gamerules.json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let object = Dictionary(uniqueKeysWithValues: self.gamerules.map { ($0.name, $0.value) })
                try JSONEncoder.pretty.encode(JSONValue.object(object)).write(to: url, options: [.atomic])
            } catch { self.lastError = error.localizedDescription }
        }
    }

    func importGamerules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let data = try Data(contentsOf: url)
                let value = try JSONDecoder().decode(JSONValue.self, from: data)
                let imported = GameruleEntry.list(from: value, favorites: self.favoriteGamerules)
                for entry in imported { self.updateGamerule(entry, value: entry.value) }
            } catch { self.lastError = error.localizedDescription }
        }
    }

    func broadcastSystemMessage(_ text: String, overlay: Bool) {
        let params: JSONValue = .object([
            "overlay": .bool(overlay),
            "message": .object(["literal": .string(text)])
        ])
        Task { await broadcastSystemMessageWithFallback(params) }
    }

    func saveServer() {
        Task { await performQuickRPC(methods: ["minecraft:server/save"], params: .object(["flush": .bool(true)]), title: "Save server") }
    }

    func stopServer() {
        Task { await performQuickRPC(methods: ["minecraft:server/stop"], params: nil, title: "Stop server") }
    }

    func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(profile.displayName)-logs.txt"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let text = self.serverLogs.map { "[\($0.date.ISO8601Format())] \($0.title): \($0.message)" }.joined(separator: "\n")
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { self.lastError = error.localizedDescription }
        }
    }

    private func bootstrap() async {
        isBootstrapped = false
        appendLog(kind: .connection, title: "Connected", message: "Negotiating capabilities")
        lastConnectedAt = Date()
        reconnectAttempts = 0
        if profile.notifications.serverOnline {
            notificationService.notify(title: "Server online", body: profile.displayName)
        }
        do {
            let discovery = try await call("rpc.discover")
            var discovered = RPCMethodDescriptor.fromDiscovery(discovery)
            if discovered.isEmpty {
                discovered = defaultMethodDescriptors
            }
            methods = discovered
            try? await schemaCache.save(methods: discovered, for: profile.id)
            appendLog(kind: .rpc, title: "Discovery complete", message: "\(discovered.count) methods available")
        } catch {
            appendLog(kind: .warning, title: "Discovery failed", message: error.localizedDescription)
            if methods.isEmpty { methods = defaultMethodDescriptors }
        }
        await refreshSnapshot()
        await loadServerSettings()
        await loadGamerules()
        isBootstrapped = true
        startPolling()
    }

    private func loadGamerules() async {
        do {
            let value = try await call("minecraft:gamerules")
            gamerules = GameruleEntry.list(from: value, favorites: favoriteGamerules)
        } catch {
            appendLog(kind: .warning, title: "Gamerules unavailable", message: error.localizedDescription)
        }
    }

    private func loadServerSettings() async {
        guard state == .connected else { return }
        async let autosave = optionalCall("minecraft:serversettings/autosave")
        async let difficulty = optionalCall("minecraft:serversettings/difficulty")
        async let maxPlayers = optionalCall("minecraft:serversettings/max_players")
        async let idleTimeout = optionalCall("minecraft:serversettings/player_idle_timeout")
        async let allowFlight = optionalCall("minecraft:serversettings/allow_flight")
        async let motd = optionalCall("minecraft:serversettings/motd")
        async let spawnProtection = optionalCall("minecraft:serversettings/spawn_protection_radius")
        async let gamemode = optionalCall("minecraft:serversettings/game_mode")
        async let viewDistance = optionalCall("minecraft:serversettings/view_distance")
        async let simulationDistance = optionalCall("minecraft:serversettings/simulation_distance")
        async let enforceAllowlist = optionalCall("minecraft:serversettings/enforce_allowlist")
        async let hideOnlinePlayers = optionalCall("minecraft:serversettings/hide_online_players")

        let values = await (
            autosave, difficulty, maxPlayers, idleTimeout, allowFlight, motd,
            spawnProtection, gamemode, viewDistance, simulationDistance,
            enforceAllowlist, hideOnlinePlayers
        )

        settingsDraft.autosave = values.0?.boolValue ?? settingsDraft.autosave
        settingsDraft.difficulty = values.1?.stringValue ?? settingsDraft.difficulty
        settingsDraft.maxPlayers = values.2?.intValue ?? settingsDraft.maxPlayers
        settingsDraft.playerIdleTimeout = values.3?.intValue ?? settingsDraft.playerIdleTimeout
        settingsDraft.allowFlight = values.4?.boolValue ?? settingsDraft.allowFlight
        settingsDraft.motd = values.5?.stringValue ?? settingsDraft.motd
        settingsDraft.spawnProtection = values.6?.intValue ?? settingsDraft.spawnProtection
        settingsDraft.gamemode = values.7?.stringValue ?? settingsDraft.gamemode
        settingsDraft.viewDistance = values.8?.intValue ?? settingsDraft.viewDistance
        settingsDraft.simulationDistance = values.9?.intValue ?? settingsDraft.simulationDistance
        settingsDraft.enforceAllowlist = values.10?.boolValue ?? settingsDraft.enforceAllowlist
        settingsDraft.hideOnlinePlayers = values.11?.boolValue ?? settingsDraft.hideOnlinePlayers

        status.maxPlayers = settingsDraft.maxPlayers
        status.viewDistance = settingsDraft.viewDistance
        status.simulationDistance = settingsDraft.simulationDistance
        status.autosaveEnabled = settingsDraft.autosave
        status.motd = settingsDraft.motd
        status.difficulty = settingsDraft.difficulty
        status.gamemode = settingsDraft.gamemode
    }

    private func optionalCall(_ method: String) async -> JSONValue? {
        do { return try await call(method) }
        catch { return nil }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self.refreshSnapshot()
            }
        }
    }

    private func performQuickRPC(methods candidateMethods: [String], params: JSONValue?, title: String) async {
        guard state == .connected else {
            appendLog(kind: .warning, title: title, message: "Not connected")
            return
        }
        let available = Set(methods.map(\.method))
        let method = candidateMethods.first { available.contains($0) } ?? candidateMethods[0]
        do {
            _ = try await call(method, params: params)
            appendLog(kind: .rpc, title: title, message: method)
            await refreshSnapshot()
            await loadServerSettings()
        } catch {
            appendLog(kind: .error, title: title, message: error.localizedDescription)
        }
    }

    private func handle(_ event: RPCClientEvent) async {
        switch event {
        case .connectionState(let newState):
            state = newState
            appendLog(kind: .connection, title: newState.label, message: profile.endpoint)
            if newState == .offline || newState == .failed {
                handleDisconnectForReconnect()
            }
        case .notification(let notification):
            handleNotification(notification)
        case .frame(let frame):
            frames.insert(frame, at: 0)
            frames = Array(frames.prefix(500))
        case .decodeFailure(let raw, let message):
            appendLog(kind: .warning, title: "Malformed packet recovered", message: message)
            frames.insert(WebSocketFrameRecord(direction: .inbound, payload: raw, isError: true), at: 0)
        }
    }

    private func handleNotification(_ notification: RPCNotification) {
        let method = notification.method.lowercased()
        if method.contains("player") && method.contains("join") {
            let name = notification.params?.value(anyOf: ["player.name", "name", "player"])?.stringValue ?? "Player"
            appendLog(kind: .player, title: "Player joined", message: name)
            if profile.notifications.playerJoined { notificationService.notify(title: "Player joined", body: "\(name) on \(profile.displayName)") }
            Task { await refreshSnapshot() }
        } else if method.contains("player") && method.contains("left") || method.contains("player") && method.contains("quit") {
            let name = notification.params?.value(anyOf: ["player.name", "name", "player"])?.stringValue ?? "Player"
            appendLog(kind: .player, title: "Player left", message: name)
            if profile.notifications.playerLeft { notificationService.notify(title: "Player left", body: "\(name) on \(profile.displayName)") }
            Task { await refreshSnapshot() }
        } else if method.contains("save") {
            appendLog(kind: .save, title: "Save event", message: notification.params?.prettyPrinted ?? notification.method)
            if method.contains("complete"), profile.notifications.autosaveComplete {
                notificationService.notify(title: "Autosave complete", body: profile.displayName)
            }
        } else if method.contains("gamerule") {
            appendLog(kind: .gamerule, title: "Gamerule updated", message: notification.params?.prettyPrinted ?? notification.method)
            Task { await loadGamerules() }
        } else if method.contains("operator") || method.contains("op") {
            appendLog(kind: .operatorChange, title: "Operator change", message: notification.params?.prettyPrinted ?? notification.method)
            Task { await refreshSnapshot() }
        } else if method.contains("log") {
            let line = notification.params?.value(anyOf: ["line", "message", "text"])?.stringValue ?? notification.params?.prettyPrinted ?? notification.method
            appendServerLog(line)
        } else if method.contains("status") || method.contains("heartbeat") {
            if let params = notification.params { applyStatus(params) }
        } else {
            appendLog(kind: .rpc, title: notification.method, message: notification.params?.prettyPrinted ?? "Notification")
        }
    }

    private func handleDisconnectForReconnect() {
        pollTask?.cancel()
        if profile.notifications.connectionLost {
            notificationService.notify(title: "Connection lost", body: profile.displayName)
        }
        guard !manualDisconnect, profile.autoReconnect else { return }
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 60)
        state = .reconnecting
        appendLog(kind: .connection, title: "Reconnect scheduled", message: "Retrying in \(Int(delay))s")
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.connect()
        }
    }

    private func connectionFailed(_ error: Error) async {
        lastError = error.localizedDescription
        state = .failed
        appendLog(kind: .error, title: "Connection failed", message: error.localizedDescription)
        handleDisconnectForReconnect()
    }

    private func applyStatus(_ value: JSONValue) {
        let previous = status
        var updated = ServerStatus.fromJSON(value)
        updated.maxPlayers = updated.maxPlayers ?? previous.maxPlayers
        updated.viewDistance = updated.viewDistance ?? previous.viewDistance
        updated.simulationDistance = updated.simulationDistance ?? previous.simulationDistance
        updated.autosaveEnabled = updated.autosaveEnabled ?? previous.autosaveEnabled
        updated.motd = updated.motd ?? previous.motd
        updated.difficulty = updated.difficulty ?? previous.difficulty
        updated.gamemode = updated.gamemode ?? previous.gamemode
        updated.memoryUsedMB = updated.memoryUsedMB ?? previous.memoryUsedMB
        updated.memoryMaxMB = updated.memoryMaxMB ?? previous.memoryMaxMB
        status = updated
        settingsDraft.merge(status: status)
        let source = value.value(for: "status") ?? value
        if source.value(for: "players")?.arrayValue != nil {
            players = MCPlayer.list(from: source)
        }
        if let used = status.memoryUsedMB { appendMemorySample(used) }
        if let count = status.playerCount { appendPlayerSample(Double(count)) }
    }

    private func appendMemorySample(_ value: Double) {
        memorySamples.append(MetricSample(value: value))
        memorySamples = Array(memorySamples.suffix(160))
    }

    private func appendPlayerSample(_ value: Double? = nil) {
        let count = value ?? Double(players.count)
        playerSamples.append(MetricSample(value: count))
        playerSamples = Array(playerSamples.suffix(160))
    }

    private func appendLatencySample(_ value: Double) {
        latencySamples.append(MetricSample(value: value))
        latencySamples = Array(latencySamples.suffix(160))
    }

    private func appendLog(kind: ActivityEvent.Kind, title: String, message: String) {
        let event = ActivityEvent(kind: kind, title: title, message: message)
        activity.insert(event, at: 0)
        activity = Array(activity.prefix(250))
        connectionLogs.insert(event, at: 0)
        connectionLogs = Array(connectionLogs.prefix(250))
        if kind == .error { logger.error("\(title, privacy: .public): \(message, privacy: .public)") }
    }

    private func appendServerLog(_ line: String) {
        let event = ActivityEvent(kind: severity(for: line), title: logTitle(for: line), message: stripANSI(line))
        serverLogs.insert(event, at: 0)
        serverLogs = Array(serverLogs.prefix(2_000))
    }

    private func severity(for line: String) -> ActivityEvent.Kind {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("exception") { return .error }
        if lower.contains("warn") { return .warning }
        return .log
    }

    private func logTitle(for line: String) -> String {
        let lower = line.lowercased()
        if lower.contains("error") { return "ERROR" }
        if lower.contains("warn") { return "WARN" }
        return "INFO"
    }

    private func stripANSI(_ string: String) -> String {
        string.replacingOccurrences(of: #"\u001B\[[0-9;]*m"#, with: "", options: .regularExpression)
    }

    private func playerJSON(_ player: MCPlayer) -> JSONValue {
        var object: [String: JSONValue] = ["name": .string(player.name)]
        if let uuid = player.uuid { object["id"] = .string(uuid) }
        return .object(object)
    }

    private func broadcastSystemMessageWithFallback(_ directParams: JSONValue) async {
        guard state == .connected else {
            appendLog(kind: .warning, title: "Broadcast message", message: "Not connected")
            return
        }

        do {
            _ = try await call("minecraft:server/system_message", params: directParams)
            appendLog(kind: .rpc, title: "Broadcast message", message: "minecraft:server/system_message")
        } catch {
            // Some OpenRPC implementations require the single parameter to be named "message".
            let nestedParams: JSONValue = .object(["message": directParams])
            do {
                _ = try await call("minecraft:server/system_message", params: nestedParams)
                appendLog(kind: .rpc, title: "Broadcast message", message: "minecraft:server/system_message")
            } catch {
                appendLog(kind: .error, title: "Broadcast message", message: error.localizedDescription)
            }
        }
    }

    private func settingRPC(for key: String, value: JSONValue) -> (method: String, params: JSONValue)? {
        switch key {
        case "view-distance":
            return ("minecraft:serversettings/view_distance/set", .object(["distance": value]))
        case "simulation-distance":
            return ("minecraft:serversettings/simulation_distance/set", .object(["distance": value]))
        case "max-players":
            return ("minecraft:serversettings/max_players/set", .object(["max": value]))
        case "motd":
            return ("minecraft:serversettings/motd/set", .object(["message": value]))
        case "difficulty":
            return ("minecraft:serversettings/difficulty/set", .object(["difficulty": value]))
        case "gamemode":
            return ("minecraft:serversettings/game_mode/set", .object(["mode": value]))
        case "autosave":
            return ("minecraft:serversettings/autosave/set", .object(["enable": value]))
        case "allow-flight":
            return ("minecraft:serversettings/allow_flight/set", .object(["allow": value]))
        case "player-idle-timeout":
            return ("minecraft:serversettings/player_idle_timeout/set", .object(["seconds": value]))
        case "spawn-protection":
            return ("minecraft:serversettings/spawn_protection_radius/set", .object(["radius": value]))
        case "hide-online-players":
            return ("minecraft:serversettings/hide_online_players/set", .object(["hide": value]))
        case "enforce-allowlist":
            return ("minecraft:serversettings/enforce_allowlist/set", .object(["enforce": value]))
        default:
            return nil
        }
    }

    private func defaultSettingValue(for key: String) -> JSONValue? {
        switch key {
        case "view-distance": return .number(10)
        case "simulation-distance": return .number(10)
        case "max-players": return .number(20)
        case "motd": return .string("A Minecraft Server")
        case "difficulty": return .string("normal")
        case "gamemode": return .string("survival")
        case "autosave": return .bool(true)
        case "allow-flight": return .bool(false)
        case "player-idle-timeout": return .number(0)
        case "spawn-protection": return .number(16)
        case "hide-online-players": return .bool(false)
        case "enforce-allowlist": return .bool(false)
        default: return nil
        }
    }

    private func settingsValue(for key: String) -> JSONValue? {
        switch key {
        case "view-distance": return .number(Double(settingsDraft.viewDistance))
        case "simulation-distance": return .number(Double(settingsDraft.simulationDistance))
        case "max-players": return .number(Double(settingsDraft.maxPlayers))
        case "motd": return .string(settingsDraft.motd)
        case "difficulty": return .string(settingsDraft.difficulty)
        case "gamemode": return .string(settingsDraft.gamemode)
        case "autosave": return .bool(settingsDraft.autosave)
        case "allow-flight": return .bool(settingsDraft.allowFlight)
        case "player-idle-timeout": return .number(Double(settingsDraft.playerIdleTimeout))
        case "spawn-protection": return .number(Double(settingsDraft.spawnProtection))
        case "hide-online-players": return .bool(settingsDraft.hideOnlinePlayers)
        case "enforce-allowlist": return .bool(settingsDraft.enforceAllowlist)
        default: return nil
        }
    }

    private var defaultMethodDescriptors: [RPCMethodDescriptor] {
        [
            "rpc.discover",
            "minecraft:server/status",
            "minecraft:players",
            "minecraft:players/kick",
            "minecraft:server/system_message",
            "minecraft:server/save",
            "minecraft:server/stop",
            "minecraft:gamerules",
            "minecraft:gamerules/update",
            "minecraft:serversettings/autosave",
            "minecraft:serversettings/autosave/set",
            "minecraft:serversettings/view_distance",
            "minecraft:serversettings/view_distance/set",
            "minecraft:serversettings/simulation_distance",
            "minecraft:serversettings/simulation_distance/set",
            "minecraft:operators/add",
            "minecraft:operators/remove",
            "minecraft:allowlist/add",
            "minecraft:allowlist/remove",
            "minecraft:bans/add"
        ].map(RPCMethodDescriptor.fallback(method:))
    }
}

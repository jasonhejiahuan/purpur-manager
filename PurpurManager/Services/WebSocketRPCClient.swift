import Foundation
import OSLog

actor WebSocketRPCClient {
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var nextID = 1
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var eventContinuation: AsyncStream<RPCClientEvent>.Continuation?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "PurpurManager", category: "WebSocketRPCClient")

    func makeEventStream() -> AsyncStream<RPCClientEvent> {
        AsyncStream { continuation in
            eventContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearEventContinuation() }
            }
        }
    }

    private func clearEventContinuation() {
        eventContinuation = nil
    }

    func connect(profile: ServerProfile, token: String?) async throws {
        await disconnect(code: .goingAway, reason: "Reconnect".data(using: .utf8), emitState: false)
        emit(.connectionState(.connecting))
        guard let url = URL(string: profile.endpoint) else {
            emit(.connectionState(.failed))
            throw RPCClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.maximumMessageSize = 16 * 1024 * 1024
        task = socket
        socket.resume()
        emit(.connectionState(.connected))
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func disconnect(code: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil, emitState: Bool = true) async {
        receiveTask?.cancel()
        receiveTask = nil
        for (_, continuation) in pending {
            continuation.resume(throwing: RPCClientError.disconnected)
        }
        pending.removeAll()
        task?.cancel(with: code, reason: reason)
        task = nil
        if emitState { emit(.connectionState(.disconnected)) }
    }

    func call(method: String, params: JSONValue? = nil, timeoutSeconds: TimeInterval = 30) async throws -> JSONValue {
        guard let socket = task else { throw RPCClientError.notConnected }
        let id = RPCID.int(nextID)
        nextID += 1
        let request = RPCRequest(id: id, method: method, params: params)
        let data = try encoder.encode(request)
        guard let text = String(data: data, encoding: .utf8) else { throw RPCClientError.malformedResponse }
        emit(.frame(WebSocketFrameRecord(direction: .outbound, payload: text, method: method, rpcID: id.description)))

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: JSONValue.self) { group in
                group.addTask { [weak self] in
                    try await self?.sendAndWait(socket: socket, text: text, id: id) ?? .null
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    throw RPCClientError.timeout
                }
                guard let result = try await group.next() else { throw RPCClientError.timeout }
                group.cancelAll()
                return result
            }
        } onCancel: {
            Task { await self.cancelPending(id: id, error: RPCClientError.disconnected) }
        }
    }

    func sendRaw(_ text: String) async throws {
        guard let socket = task else { throw RPCClientError.notConnected }
        emit(.frame(WebSocketFrameRecord(direction: .outbound, payload: text, method: nil, rpcID: nil)))
        try await socket.send(.string(text))
    }

    func ping() async throws -> TimeInterval {
        guard let socket = task else { throw RPCClientError.notConnected }
        let start = Date()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        return Date().timeIntervalSince(start)
    }

    private func sendAndWait(socket: URLSessionWebSocketTask, text: String, id: RPCID) async throws -> JSONValue {
        try await withCheckedThrowingContinuation { continuation in
            pending[id.description] = continuation
            Task {
                do {
                    try await socket.send(.string(text))
                } catch {
                    await self.cancelPending(id: id, error: error)
                }
            }
        }
    }

    private func cancelPending(id: RPCID, error: Error) {
        pending.removeValue(forKey: id.description)?.resume(throwing: error)
    }

    private func receiveLoop() async {
        while !Task.isCancelled, let socket = task {
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text): handle(text: text)
                case .data(let data):
                    let text = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
                    handle(text: text)
                @unknown default:
                    emit(.decodeFailure(raw: "<unknown frame>", message: "Received an unknown WebSocket frame type."))
                }
            } catch {
                logger.error("Receive loop failed: \(error.localizedDescription, privacy: .public)")
                task = nil
                for (_, continuation) in pending {
                    continuation.resume(throwing: error)
                }
                pending.removeAll()
                emit(.connectionState(.offline))
                return
            }
        }
    }

    private func handle(text: String) {
        let envelope: RPCEnvelope
        do {
            envelope = try decoder.decode(RPCEnvelope.self, from: Data(text.utf8))
        } catch {
            emit(.frame(WebSocketFrameRecord(direction: .inbound, payload: text, isError: true)))
            emit(.decodeFailure(raw: text, message: error.localizedDescription))
            return
        }

        emit(.frame(WebSocketFrameRecord(direction: .inbound,
                                         payload: text,
                                         method: envelope.method,
                                         rpcID: envelope.id?.description,
                                         isError: envelope.error != nil)))

        if let id = envelope.id {
            if let continuation = pending.removeValue(forKey: id.description) {
                if let error = envelope.error {
                    continuation.resume(throwing: error)
                } else if let result = envelope.result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(returning: .null)
                }
            }
        } else if let method = envelope.method {
            emit(.notification(RPCNotification(method: method, params: envelope.params)))
        }
    }

    private func emit(_ event: RPCClientEvent) {
        eventContinuation?.yield(event)
    }
}

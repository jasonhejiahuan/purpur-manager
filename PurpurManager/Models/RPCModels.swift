import Foundation

enum RPCID: Codable, Hashable, Sendable, CustomStringConvertible {
    case int(Int)
    case string(String)

    var description: String {
        switch self {
        case .int(let value): return String(value)
        case .string(let value): return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.typeMismatch(RPCID.self, .init(codingPath: decoder.codingPath, debugDescription: "JSON-RPC id must be a string or integer"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

struct RPCErrorObject: Codable, Error, Hashable, Sendable, CustomStringConvertible {
    var code: Int
    var message: String
    var data: JSONValue?

    var description: String { "RPC Error \(code): \(message)" }
}

struct RPCRequest: Codable, Hashable, Sendable {
    var jsonrpc = "2.0"
    var id: RPCID
    var method: String
    var params: JSONValue?
}

struct RPCEnvelope: Codable, Hashable, Sendable {
    var jsonrpc: String?
    var id: RPCID?
    var method: String?
    var params: JSONValue?
    var result: JSONValue?
    var error: RPCErrorObject?
}

struct RPCNotification: Identifiable, Hashable, Sendable {
    var id = UUID()
    var method: String
    var params: JSONValue?
    var receivedAt = Date()
}

struct RPCMethodDescriptor: Identifiable, Codable, Hashable, Sendable {
    var id: String { method }
    var method: String
    var summary: String
    var paramsSchema: JSONValue?
    var resultSchema: JSONValue?
    var raw: JSONValue?

    static func fallback(method: String) -> RPCMethodDescriptor {
        RPCMethodDescriptor(method: method, summary: "Discovered method", paramsSchema: nil, resultSchema: nil, raw: nil)
    }

    static func fromDiscovery(_ value: JSONValue) -> [RPCMethodDescriptor] {
        if let methods = value.value(anyOf: ["methods", "result.methods"])?.arrayValue {
            return methods.compactMap(parseMethodValue)
        }
        if let object = value.objectValue {
            if let methodsObject = object["methods"]?.objectValue {
                return methodsObject.map { key, value in
                    parseMethodValue(value) ?? RPCMethodDescriptor(method: key, summary: value.value(for: "description")?.stringValue ?? "Discovered method", paramsSchema: value.value(anyOf: ["params", "paramsSchema", "parameters"]), resultSchema: value.value(anyOf: ["result", "resultSchema"]), raw: value)
                }.sorted { $0.method < $1.method }
            }
            return object.compactMap { key, value in
                guard key.contains(":") || key.contains(".") else { return nil }
                return RPCMethodDescriptor(method: key, summary: value.value(for: "description")?.stringValue ?? "Discovered method", paramsSchema: value.value(anyOf: ["params", "paramsSchema", "parameters"]), resultSchema: value.value(anyOf: ["result", "resultSchema"]), raw: value)
            }.sorted { $0.method < $1.method }
        }
        return []
    }

    private static func parseMethodValue(_ value: JSONValue) -> RPCMethodDescriptor? {
        if let method = value.stringValue, method.contains(":") || method.contains(".") {
            return RPCMethodDescriptor.fallback(method: method)
        }
        guard let object = value.objectValue else { return nil }
        let method = object["method"]?.stringValue ?? object["name"]?.stringValue ?? object["id"]?.stringValue
        guard let method else { return nil }
        return RPCMethodDescriptor(method: method,
                                   summary: object["description"]?.stringValue ?? object["summary"]?.stringValue ?? "Discovered method",
                                   paramsSchema: object["params"] ?? object["paramsSchema"] ?? object["parameters"],
                                   resultSchema: object["result"] ?? object["resultSchema"],
                                   raw: value)
    }
}

struct WebSocketFrameRecord: Identifiable, Hashable, Sendable {
    enum Direction: String, Codable, Sendable { case inbound, outbound }
    var id = UUID()
    var date = Date()
    var direction: Direction
    var payload: String
    var method: String?
    var rpcID: String?
    var isError: Bool = false

    var compactPayload: String {
        payload.replacingOccurrences(of: "\n", with: " ").prefix(220).description
    }
}

enum RPCClientEvent: Sendable {
    case connectionState(ConnectionState)
    case notification(RPCNotification)
    case frame(WebSocketFrameRecord)
    case decodeFailure(raw: String, message: String)
}

enum RPCClientError: LocalizedError, Sendable {
    case invalidURL
    case notConnected
    case disconnected
    case malformedResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The server URL is invalid."
        case .notConnected: return "The WebSocket is not connected."
        case .disconnected: return "The WebSocket disconnected."
        case .malformedResponse: return "The server returned a malformed JSON-RPC response."
        case .timeout: return "The JSON-RPC request timed out."
        }
    }
}

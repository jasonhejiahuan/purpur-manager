import Foundation

/// A strongly-typed representation of arbitrary JSON used by the dynamic JSON-RPC API.
enum JSONValue: Codable, Hashable, Sendable, Identifiable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var id: String { stableDescription }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value):
            if value.rounded() == value, value >= Double(Int.min), value <= Double(Int.max) {
                try container.encode(Int(value))
            } else {
                try container.encode(value)
            }
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.formatted()
        case .bool(let value): return value ? "true" : "false"
        case .null: return nil
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value):
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        case .number(let value): return value != 0
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    var prettyPrinted: String {
        guard let data = try? JSONEncoder.pretty.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return stableDescription
        }
        return string
    }

    var stableDescription: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.formatted()
        case .bool(let value): return String(value)
        case .null: return "null"
        case .array(let values): return "[" + values.map(\.stableDescription).joined(separator: ",") + "]"
        case .object(let object):
            return "{" + object.keys.sorted().map { key in "\(key):\(object[key]?.stableDescription ?? "null")" }.joined(separator: ",") + "}"
        }
    }

    func value(for keyPath: String) -> JSONValue? {
        let parts = keyPath.split(separator: ".").map(String.init)
        return parts.reduce(Optional(self)) { partial, key in
            guard let object = partial?.objectValue else { return nil }
            return object[key]
        }
    }

    func value(anyOf keys: [String]) -> JSONValue? {
        for key in keys {
            if let value = value(for: key) { return value }
        }
        return nil
    }

    func decoded<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static let app = JSONDecoder()
}

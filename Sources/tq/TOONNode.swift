import Foundation
import ToonFormat

/// A generic tree type that mirrors JSON/TOON data for querying and transformation.
/// Conforms to Codable so it can be decoded from TOON (via TOONDecoder) and
/// re-encoded back to TOON or JSON.
indirect enum TOONNode: Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([TOONNode])
    case object([String: TOONNode], keyOrder: [String] = [])

    // MARK: - Convenience

    var isNull: Bool { if case .null = self { true } else { false } }
    var isBool: Bool { if case .bool = self { true } else { false } }
    var isInt: Bool { if case .int = self { true } else { false } }
    var isDouble: Bool { if case .double = self { true } else { false } }
    var isString: Bool { if case .string = self { true } else { false } }
    var isArray: Bool { if case .array = self { true } else { false } }
    var isObject: Bool { if case .object = self { true } else { false } }

    var boolValue: Bool? { if case let .bool(v) = self { v } else { nil } }
    var intValue: Int64? { if case let .int(v) = self { v } else { nil } }
    var doubleValue: Double? {
        if case let .double(v) = self { v }
        else if case let .int(v) = self { Double(v) }
        else { nil }
    }
    var stringValue: String? { if case let .string(v) = self { v } else { nil } }
    var arrayValue: [TOONNode]? { if case let .array(v) = self { v } else { nil } }
    var objectValue: (values: [String: TOONNode], keyOrder: [String])? {
        if case let .object(v, k) = self { (v, k) } else { nil }
    }

    /// Access a child by key or index. Returns nil if not applicable.
    subscript(key: String) -> TOONNode? {
        if case let .object(dict, _) = self { return dict[key] }
        return nil
    }

    subscript(index: Int) -> TOONNode? {
        guard case let .array(arr) = self else { return nil }
        let idx = index < 0 ? arr.count + index : index
        guard idx >= 0, idx < arr.count else { return nil }
        return arr[idx]
    }
}

// MARK: - Codable

extension TOONNode: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int64.self) {
            // Distinguish Int64 from Double by checking if the same token parses as Double
            // If it's a pure integer token, treat as int; otherwise double
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([TOONNode].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: TOONNode].self) {
            // Dictionary preserves key ordering in Swift, but our internal format tracks it
            self = .object(dict, keyOrder: Array(dict.keys))
        } else {
            let ctx = DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported TOON value type"
            )
            throw DecodingError.dataCorrupted(ctx)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(dict, _):
            try container.encode(dict)
        }
    }
}

// MARK: - JSON Output

extension TOONNode {
    /// Convert the node to pretty-printed JSON Data.
    func toJSONData(pretty: Bool = true) throws -> Data {
        let obj = toJSONCompatible()
        var options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        // Allow fragments (bare strings, numbers, etc.) as top-level JSON
        if !(obj is [String: Any] || obj is [Any]) {
            options.insert(.fragmentsAllowed)
        }
        return try JSONSerialization.data(withJSONObject: obj, options: options)
    }

    /// Convert to a Foundation JSON-compatible value ([String: Any], [Any], etc.)
    func toJSONCompatible() -> Any {
        switch self {
        case .null:
            return NSNull()
        case let .bool(v):
            return v
        case let .int(v):
            return v
        case let .double(v):
            return v
        case let .string(v):
            return v
        case let .array(v):
            return v.map { $0.toJSONCompatible() }
        case let .object(dict, keyOrder):
            // Build an ordered dictionary-like representation
            var result: [String: Any] = [:]
            // Use keyOrder if available, otherwise dict keys
            let keys = keyOrder.isEmpty ? Array(dict.keys) : keyOrder
            for key in keys {
                if let val = dict[key] {
                    result[key] = val.toJSONCompatible()
                }
            }
            return result
        }
    }

    /// JSON string representation.
    func toJSONString(pretty: Bool = true) throws -> String {
        let data = try toJSONData(pretty: pretty)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - TOON Output

extension TOONNode {
    /// Encode the node back to TOON format using TOONEncoder.
    func toTOONData() throws -> Data {
        let encoder = TOONEncoder()
        encoder.keyFolding = .safe
        return try encoder.encode(self)
    }

    /// TOON string representation.
    func toTOONString() throws -> String {
        let data = try toTOONData()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

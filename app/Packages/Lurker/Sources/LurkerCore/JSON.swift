import Foundation

/// Any JSON value. Carries `set` op values, generic region updates and open-ended settings (backgrounds).
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        // whole numbers go out as integers so Int fields decode from them
        case .number(let n): if n.rounded() == n, abs(n) < 9e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Round-trips any Encodable through JSON.
    public static func from<T: Encodable>(_ value: T) throws -> JSONValue {
        try LurkerJSON.decoder().decode(JSONValue.self, from: LurkerJSON.encoder().encode(value))
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try LurkerJSON.decoder().decode(T.self, from: LurkerJSON.encoder().encode(self))
    }

    /// The value at a dotted path, or nil when any step is missing.
    public func value<S: Collection>(at path: S) -> JSONValue? where S.Element == String {
        guard let key = path.first else { return self }
        guard case .object(let o) = self, let next = o[key] else { return nil }
        return next.value(at: path.dropFirst())
    }

    /// A copy with `value` written at the path, creating objects on the way. `.null` removes the key.
    public func setting<S: Collection>(_ path: S, to value: JSONValue) throws -> JSONValue where S.Element == String {
        guard let key = path.first else { return value }
        var o: [String: JSONValue]
        switch self {
        case .object(let existing): o = existing
        case .null: o = [:]
        default: throw LurkerJSON.PathError(key: key)
        }
        let rest = path.dropFirst()
        if rest.isEmpty && value == .null { o.removeValue(forKey: key) }
        else { o[key] = try (o[key] ?? .null).setting(rest, to: value) }
        return .object(o)
    }

    public var keys: [String] { if case .object(let o) = self { return o.keys.sorted() } else { return [] } }
}

public enum LurkerJSON {
    /// Sorted, readable, stable output so project files diff cleanly.
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
    /// One object per line, for journals and NDJSON.
    public static func lineEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
    public static func decoder() -> JSONDecoder { JSONDecoder() }

    struct PathError: Error, CustomStringConvertible {
        let key: String
        var description: String { "\(key) is inside a value that isn't an object" }
    }

    /// "canvas.padding: Expected Double but found a string" instead of Foundation's nested error dump.
    public static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return "\(error)" }
        let context: DecodingError.Context
        switch e {
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c), .dataCorrupted(let c): context = c
        @unknown default: return "\(e)"
        }
        var path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
        if case .keyNotFound(let key, _) = e { path.append(key.stringValue) }
        let joined = path.joined(separator: ".").replacingOccurrences(of: ".[", with: "[")
        return joined.isEmpty ? context.debugDescription : "\(joined): \(context.debugDescription)"
    }
}

extension KeyedDecodingContainer {
    /// Missing keys fall back to a default, so project files only hold what differs.
    func decode<T: Decodable>(_ key: Key, or fallback: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback()
    }
}

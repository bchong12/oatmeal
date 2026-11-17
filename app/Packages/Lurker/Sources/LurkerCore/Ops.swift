import Foundation

/// Which clock an op's start/end are on. Source: seconds inside a take. Program: seconds in the finished video.
public enum Timebase: String, Codable, Sendable { case source, program }

/// A batch of ops applied atomically as one undo step.
public struct EditBatch: Codable, Equatable, Sendable {
    /// The rev the ops were written against; a mismatch is refused. nil skips the check (humans at a CLI).
    public var baseRev: Int?
    public var label: String?
    public var timebase: Timebase?
    public var dryRun: Bool?
    public var ops: [Op]

    public init(ops: [Op], baseRev: Int? = nil, label: String? = nil, timebase: Timebase? = nil, dryRun: Bool? = nil) {
        self.ops = ops; self.baseRev = baseRev; self.label = label; self.timebase = timebase; self.dryRun = dryRun
    }
}

/// One edit. Wire format: {"op": "add_zoom", "start": 3, "end": 6, "depth": 2}.
public enum Op: Codable, Equatable, Sendable {
    case addClip(AddClip)
    case moveClip(MoveClip)
    case trimClip(TrimClip)
    case cut(Span)
    case restore(Span)
    case setSpeed(SetSpeed)
    case addZoom(AddZoom)
    case addMask(AddMask)
    case update(Update)
    case remove(Target)
    case set(SetValue)
    case note(Note)

    public struct AddClip: Codable, Equatable, Sendable {
        public var take: String
        public var start: Double?
        public var end: Double?
        /// Position in program order; default last.
        public var at: Int?
        public init(take: String, start: Double? = nil, end: Double? = nil, at: Int? = nil) { self.take = take; self.start = start; self.end = end; self.at = at }
    }
    public struct MoveClip: Codable, Equatable, Sendable {
        public var id: String
        public var to: Int
        public init(id: String, to: Int) { self.id = id; self.to = to }
    }
    public struct TrimClip: Codable, Equatable, Sendable {
        public var id: String
        public var start: Double?
        public var end: Double?
        public init(id: String, start: Double? = nil, end: Double? = nil) { self.id = id; self.start = start; self.end = end }
    }
    /// A time range. `take` is only for source time and may be left out when the project has one take.
    public struct Span: Codable, Equatable, Sendable {
        public var take: String?
        public var start: Double
        public var end: Double
        public init(take: String? = nil, start: Double, end: Double) { self.take = take; self.start = start; self.end = end }
    }
    public struct SetSpeed: Codable, Equatable, Sendable {
        public var take: String?
        public var start: Double
        public var end: Double
        /// 1 removes any speed change in the range.
        public var rate: Double
        public var audio: Speed.Audio?
        public init(take: String? = nil, start: Double, end: Double, rate: Double, audio: Speed.Audio? = nil) {
            self.take = take; self.start = start; self.end = end; self.rate = rate; self.audio = audio
        }
    }
    public struct AddZoom: Codable, Equatable, Sendable {
        public var take: String?
        public var start: Double
        public var end: Double
        public var depth: Double?
        public var x: Double?
        public var y: Double?
        public var instant: Bool?
        public init(take: String? = nil, start: Double, end: Double, depth: Double? = nil, x: Double? = nil, y: Double? = nil, instant: Bool? = nil) {
            self.take = take; self.start = start; self.end = end; self.depth = depth; self.x = x; self.y = y; self.instant = instant
        }
    }
    public struct AddMask: Codable, Equatable, Sendable {
        public var take: String?
        public var start: Double
        public var end: Double
        public var effect: Mask.Effect?
        public var rect: [Double]
        public var track: Mask.Track?
        public init(take: String? = nil, start: Double, end: Double, effect: Mask.Effect? = nil, rect: [Double], track: Mask.Track? = nil) {
            self.take = take; self.start = start; self.end = end; self.effect = effect; self.rect = rect; self.track = track
        }
    }
    /// Change fields of any region by id. null removes an optional field.
    public struct Update: Codable, Equatable, Sendable {
        public var id: String
        public var fields: [String: JSONValue]
        public init(id: String, fields: [String: JSONValue]) { self.id = id; self.fields = fields }
    }
    /// A clip or region id.
    public struct Target: Codable, Equatable, Sendable {
        public var id: String
        public init(id: String) { self.id = id }
    }
    /// Write a setting by dotted path, e.g. canvas.padding. null resets it to the default.
    public struct SetValue: Codable, Equatable, Sendable {
        public var path: String
        public var value: JSONValue
        public init(path: String, value: JSONValue) { self.path = path; self.value = value }
    }
    /// Changes nothing; lands in the history (why an edit was made).
    public struct Note: Codable, Equatable, Sendable {
        public var text: String
        public init(text: String) { self.text = text }
    }

    public static let names = ["add_clip", "move_clip", "trim_clip", "cut", "restore", "set_speed", "add_zoom",
                               "add_mask", "update", "remove", "set", "note"]

    public var name: String {
        switch self {
        case .addClip: "add_clip"
        case .moveClip: "move_clip"
        case .trimClip: "trim_clip"
        case .cut: "cut"
        case .restore: "restore"
        case .setSpeed: "set_speed"
        case .addZoom: "add_zoom"
        case .addMask: "add_mask"
        case .update: "update"
        case .remove: "remove"
        case .set: "set"
        case .note: "note"
        }
    }

    private enum Key: String, CodingKey { case op }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let name = try c.decode(String.self, forKey: .op)
        switch name {
        case "add_clip": self = .addClip(try AddClip(from: decoder))
        case "move_clip": self = .moveClip(try MoveClip(from: decoder))
        case "trim_clip": self = .trimClip(try TrimClip(from: decoder))
        case "cut": self = .cut(try Span(from: decoder))
        case "restore": self = .restore(try Span(from: decoder))
        case "set_speed": self = .setSpeed(try SetSpeed(from: decoder))
        case "add_zoom": self = .addZoom(try AddZoom(from: decoder))
        case "add_mask": self = .addMask(try AddMask(from: decoder))
        case "update": self = .update(try Update(from: decoder))
        case "remove": self = .remove(try Target(from: decoder))
        case "set": self = .set(try SetValue(from: decoder))
        case "note": self = .note(try Note(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .op, in: c, debugDescription: "unknown op \"\(name)\"; ops: \(Op.names.joined(separator: ", "))")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .addClip(let p): try p.encode(to: encoder)
        case .moveClip(let p): try p.encode(to: encoder)
        case .trimClip(let p): try p.encode(to: encoder)
        case .cut(let p), .restore(let p): try p.encode(to: encoder)
        case .setSpeed(let p): try p.encode(to: encoder)
        case .addZoom(let p): try p.encode(to: encoder)
        case .addMask(let p): try p.encode(to: encoder)
        case .update(let p): try p.encode(to: encoder)
        case .remove(let p): try p.encode(to: encoder)
        case .set(let p): try p.encode(to: encoder)
        case .note(let p): try p.encode(to: encoder)
        }
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(name, forKey: .op)
    }
}

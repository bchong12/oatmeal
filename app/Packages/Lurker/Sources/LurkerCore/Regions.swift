import Foundation

/// Who made a region. Planners make `auto` ones and may replace them; anything touched by a person or agent is manual.
public enum Origin: String, Codable, Sendable { case auto, manual }

/// A stretch of one take, in source seconds.
public protocol Region: Codable, Equatable, Sendable {
    static var kind: RegionKind { get }
    var id: String { get set }
    var take: String { get set }
    var start: Double { get set }
    var end: Double { get set }
    /// nil = manual
    var origin: Origin? { get set }
}

public enum RegionKind: String, Codable, CaseIterable, Sendable {
    case cut, speed, zoom, mask
}

public struct Cut: Region {
    public static let kind = RegionKind.cut
    public init(id: String = "", take: String, start: Double, end: Double, origin: Origin? = nil, reason: String? = nil) {
        self.id = id; self.take = take; self.start = start; self.end = end; self.origin = origin; self.reason = reason
    }
    public var id: String
    public var take: String
    public var start: Double
    public var end: Double
    public var origin: Origin?
    /// Why it was cut: recording (paused or interrupted), filler, pause, words; nil = by hand.
    public var reason: String?
}

public struct Speed: Region {
    public static let kind = RegionKind.speed
    /// What the audio does while sped up: keep it pitch-corrected, duck it, or mute it.
    public enum Audio: String, Codable, CaseIterable, Sendable { case keep, duck, mute }
    public var id: String
    public var take: String
    public var start: Double
    public var end: Double
    public var origin: Origin?
    /// 2 = twice as fast.
    public var rate: Double
    public var audio: Audio?
    public init(id: String = "", take: String, start: Double, end: Double, origin: Origin? = nil, rate: Double, audio: Audio? = nil) {
        self.id = id; self.take = take; self.start = start; self.end = end; self.origin = origin; self.rate = rate; self.audio = audio
    }
}

public struct Zoom: Region {
    public static let kind = RegionKind.zoom
    public var id: String
    public var take: String
    public var start: Double
    public var end: Double
    public var origin: Origin?
    /// 2 = twice as close; below 1 zooms out.
    public var depth: Double
    /// Fixed focus as shares of the screen; nil = follow the action.
    public var x: Double?
    public var y: Double?
    /// Cut straight in and out instead of animating.
    public var instant: Bool?
    public init(id: String = "", take: String, start: Double, end: Double, origin: Origin? = nil, depth: Double, x: Double? = nil, y: Double? = nil, instant: Bool? = nil) {
        self.id = id; self.take = take; self.start = start; self.end = end; self.origin = origin; self.depth = depth; self.x = x; self.y = y; self.instant = instant
    }
}

public struct Mask: Region {
    public static let kind = RegionKind.mask
    public enum Effect: String, Codable, CaseIterable, Sendable { case blur, pixelate, redact, highlight }
    public enum Track: String, Codable, CaseIterable, Sendable { case none, scroll }
    public var id: String
    public var take: String
    public var start: Double
    public var end: Double
    public var origin: Origin?
    public var effect: Mask.Effect
    /// [x, y, width, height] as shares of the screen, top-left origin.
    public var rect: [Double]
    public var track: Track?
}

public struct Regions: Codable, Equatable, Sendable {
    public var cut: [Cut] = []
    public var speed: [Speed] = []
    public var zoom: [Zoom] = []
    public var mask: [Mask] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cut = try c.decode(.cut, or: [])
        speed = try c.decode(.speed, or: [])
        zoom = try c.decode(.zoom, or: [])
        mask = try c.decode(.mask, or: [])
    }

    public var allIDs: [String] {
        cut.map(\.id) + speed.map(\.id) + zoom.map(\.id) + mask.map(\.id)
    }

    static func order<R: Region>(_ a: R, _ b: R) -> Bool { (a.take, a.start, a.end) < (b.take, b.start, b.end) }

    public func kind(of id: String) -> RegionKind? {
        if cut.contains(where: { $0.id == id }) { return .cut }
        if speed.contains(where: { $0.id == id }) { return .speed }
        if zoom.contains(where: { $0.id == id }) { return .zoom }
        if mask.contains(where: { $0.id == id }) { return .mask }
        return nil
    }

    /// The region as JSON, for generic updates.
    func json(of id: String) throws -> JSONValue? {
        if let r = cut.first(where: { $0.id == id }) { return try .from(r) }
        if let r = speed.first(where: { $0.id == id }) { return try .from(r) }
        if let r = zoom.first(where: { $0.id == id }) { return try .from(r) }
        if let r = mask.first(where: { $0.id == id }) { return try .from(r) }
        return nil
    }

    /// Replaces a region from JSON, keeping its place in the list.
    mutating func replace(_ id: String, with value: JSONValue) throws {
        func swap<R: Region>(_ list: inout [R]) throws -> Bool {
            guard let i = list.firstIndex(where: { $0.id == id }) else { return false }
            list[i] = try value.decode(R.self)
            return true
        }
        if try swap(&cut) || swap(&speed) || swap(&zoom) || swap(&mask) { return }
    }

    @discardableResult
    mutating func remove(_ id: String) -> Bool {
        let before = allIDs.count
        cut.removeAll { $0.id == id }; speed.removeAll { $0.id == id }; zoom.removeAll { $0.id == id }
        mask.removeAll { $0.id == id }
        return allIDs.count != before
    }

    /// Field names an update may set, per kind (property names are the JSON keys).
    static func fields(_ kind: RegionKind) -> [String] {
        let sample: Any
        switch kind {
        case .cut: sample = Cut(id: "", take: "", start: 0, end: 0)
        case .speed: sample = Speed(id: "", take: "", start: 0, end: 0, rate: 1)
        case .zoom: sample = Zoom(id: "", take: "", start: 0, end: 0, depth: 1)
        case .mask: sample = Mask(id: "", take: "", start: 0, end: 0, effect: .blur, rect: [])
        }
        return Mirror(reflecting: sample).children.compactMap(\.label)
    }
}

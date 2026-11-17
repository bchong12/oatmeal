import Foundation

/// The project document (project.json). Every time is in source seconds of a take; TimeMap derives program time.
/// Settings fields are optional: nil means "use the default", so files only hold what someone chose.
public struct Project: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schema = Project.schemaVersion
    /// Bumped by every change (edits, undo, redo). Edits name the rev they were made against.
    public var rev = 0
    /// Highest number handed out for an id ("zoom-12"). Ids are never reused, so a stale id can't hit a new region.
    public var serial = 0
    public var takes: [String: Take] = [:]
    /// Program order. Several clips can come from one take.
    public var clips: [Clip] = []
    public var regions = Regions()
    public var canvas = Canvas()
    public var cursor = CursorStyle()
    public var audio = AudioStyle()
    public var export = ExportSettings()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(.schema, or: Project.schemaVersion)
        rev = try c.decode(.rev, or: 0)
        serial = try c.decode(.serial, or: 0)
        takes = try c.decode(.takes, or: [:])
        clips = try c.decode(.clips, or: [])
        regions = try c.decode(.regions, or: Regions())
        canvas = try c.decode(.canvas, or: Canvas())
        cursor = try c.decode(.cursor, or: CursorStyle())
        audio = try c.decode(.audio, or: AudioStyle())
        export = try c.decode(.export, or: ExportSettings())
    }

    /// Settings sections the `set` op may write.
    public static let settingsRoots = ["canvas", "cursor", "audio", "export"]

    /// Every clip and region id.
    public var allIDs: [String] { clips.map(\.id) + regions.allIDs }

    /// A fresh id like "zoom-13".
    public mutating func newID(_ prefix: String) -> String {
        let highest = allIDs.compactMap { $0.split(separator: "-").last.flatMap { Int($0) } }.max() ?? 0
        serial = max(serial, highest) + 1
        return "\(prefix)-\(serial)"
    }

    /// The only take, when there is exactly one.
    public var soleTake: String? { takes.count == 1 ? takes.keys.first : nil }
}

/// One recording inside the bundle (takes/<id>/). Media details are filled in by capture.
public struct Take: Codable, Equatable, Sendable {
    public var duration: Double
    public var name: String?
    public var width: Int?
    public var height: Int?
    public var fps: Double?
    /// Which media files the take has: screen, system.
    public var tracks: [String]?

    public init(duration: Double, name: String? = nil, width: Int? = nil, height: Int? = nil, fps: Double? = nil, tracks: [String]? = nil) {
        self.duration = duration; self.name = name; self.width = width; self.height = height; self.fps = fps; self.tracks = tracks
    }
}

/// A stretch of a take placed on the program timeline.
public struct Clip: Codable, Equatable, Sendable {
    public var id: String
    public var take: String
    public var start: Double
    public var end: Double

    public init(id: String, take: String, start: Double, end: Double) {
        self.id = id; self.take = take; self.start = start; self.end = end
    }
}

// MARK: - settings

public struct Canvas: Codable, Equatable, Sendable {
    public enum Aspect: String, Codable, CaseIterable, Sendable {
        case auto, wide = "16:9", vertical = "9:16", square = "1:1", classic = "4:3", tall = "3:4", portrait = "4:5"
    }
    public struct Shadow: Codable, Equatable, Sendable {
        public var opacity: Double?
        public var softness: Double?
        public var angle: Double?
        public var distance: Double?
        public init() {}
    }
    public var aspect: Aspect?
    /// {type: aurora | aura | gradient | color | image | wallpaper, ...}; the engine owns the vocabulary.
    public var background: JSONValue?
    /// Share of the canvas around the screen (0–0.45).
    public var padding: Double?
    /// Corner radius in output points at 1080p.
    public var radius: Double?
    public var inset: Double?
    public var shadow: Shadow?
    /// Blur on camera moves, as a share of a 180° shutter (0 = sharp, 1 = film-like).
    public var motionBlur: Double?
    /// Window takes: keep the window's title bar (default false: cut it off).
    public var titleBar: Bool?
    public init() {}
}

public struct CursorStyle: Codable, Equatable, Sendable {
    public enum Look: String, Codable, CaseIterable, Sendable { case macos, touch, dot }
    public enum Smoothing: String, Codable, CaseIterable, Sendable { case smooth, medium, rapid, none }
    public enum Click: String, Codable, CaseIterable, Sendable { case none, ripple, circle, shockwave }
    /// recorded: the real path, smoothed. planned: a new path, moving decisively from one meaningful moment
    /// (click, drag, typing, scroll, deliberate pause) to the next; the wandering in between is dropped.
    public enum Path: String, Codable, CaseIterable, Sendable { case recorded, planned }
    public var hidden: Bool?
    public var look: Look?
    /// Multiple of the system cursor size (0.25–4).
    public var size: Double?
    public var smoothing: Smoothing?
    public var path: Path?
    public var hideWhenIdleMs: Double?
    public var click: Click?
    /// Return to where the take started, so the video loops.
    public var loop: Bool?
    public var removeShakes: Bool?
    public var motionBlur: Double?
    public init() {}
}

public struct AudioStyle: Codable, Equatable, Sendable {
    public var systemVolume: Double?
    public init() {}
}

public struct ExportSettings: Codable, Equatable, Sendable {
    public enum Preset: String, Codable, CaseIterable, Sendable { case master, youtube, social, x, web, gif }
    public enum Resolution: String, Codable, CaseIterable, Sendable {
        case native, p480 = "480p", p720 = "720p", p1080 = "1080p", p1440 = "1440p", p2160 = "4k"
    }
    public var preset: Preset?
    public var resolution: Resolution?
    public var fps: Double?
    public init() {}
}

// MARK: - validation

public struct ValidationError: Error, Equatable, CustomStringConvertible {
    public var message: String
    public var hint: String?
    public init(_ message: String, hint: String? = nil) { self.message = message; self.hint = hint }
    public var description: String { hint.map { "\(message) (\($0))" } ?? message }
}

extension Project {
    /// Times may sit this far past a take's end (float noise from program-time conversions).
    static let slack = 1e-6

    public func validate() throws {
        guard schema == Project.schemaVersion else { throw ValidationError("schema \(schema) isn't supported; this build reads \(Project.schemaVersion)") }
        var seen = Set<String>()
        for id in allIDs {
            guard seen.insert(id).inserted else { throw ValidationError("duplicate id \(id)") }
        }
        for (id, t) in takes {
            guard t.duration > 0, t.duration.isFinite else { throw ValidationError("take \(id) has duration \(t.duration)") }
        }
        for c in clips { try checkSpan(c.id, take: c.take, c.start, c.end) }
        for r in regions.cut { try checkSpan(r.id, take: r.take, r.start, r.end) }
        for r in regions.speed {
            try checkSpan(r.id, take: r.take, r.start, r.end)
            guard r.rate >= 1.0 / 32 && r.rate <= 32 else { throw ValidationError("\(r.id): rate \(r.rate) is outside 1/32–32") }
        }
        for (a, b) in zip(regions.speed.sorted(by: Regions.order), regions.speed.sorted(by: Regions.order).dropFirst())
        where a.take == b.take && b.start < a.end - Project.slack {
            throw ValidationError("\(a.id) and \(b.id) overlap", hint: "speed ranges can't overlap; set_speed replaces whatever is under it")
        }
        for r in regions.zoom {
            try checkSpan(r.id, take: r.take, r.start, r.end)
            guard r.end - r.start >= 0.1 - Project.slack else { throw ValidationError("\(r.id) is shorter than 0.1 s") }
            guard r.depth >= 0.5 && r.depth <= 6 else { throw ValidationError("\(r.id): depth \(r.depth) is outside 0.5–6", hint: "1 = no zoom, 2 = twice as close, below 1 zooms out") }
            guard (r.x == nil) == (r.y == nil) else { throw ValidationError("\(r.id): give both x and y, or neither to follow the action") }
            if let x = r.x, let y = r.y { try unit("\(r.id).x", x); try unit("\(r.id).y", y) }
        }
        for r in regions.mask {
            try checkSpan(r.id, take: r.take, r.start, r.end)
            guard r.rect.count == 4 else { throw ValidationError("\(r.id): rect is [x, y, width, height] as shares of the screen") }
            for v in r.rect { try unit("\(r.id).rect", v) }
            guard r.rect[2] > 0, r.rect[3] > 0, r.rect[0] + r.rect[2] <= 1 + Project.slack, r.rect[1] + r.rect[3] <= 1 + Project.slack else {
                throw ValidationError("\(r.id): rect must have size and stay inside the screen")
            }
        }
        try range("canvas.padding", canvas.padding, 0, 0.45)
        try range("canvas.radius", canvas.radius, 0, 512)
        try range("canvas.inset", canvas.inset, 0, 64)
        try range("canvas.shadow.opacity", canvas.shadow?.opacity, 0, 1)
        try range("canvas.shadow.softness", canvas.shadow?.softness, 0, 1)
        try range("canvas.motionBlur", canvas.motionBlur, 0, 1)
        try range("cursor.size", cursor.size, 0.25, 4)
        try range("cursor.hideWhenIdleMs", cursor.hideWhenIdleMs, 0, 60_000)
        try range("cursor.motionBlur", cursor.motionBlur, 0, 1)
        try range("audio.systemVolume", audio.systemVolume, 0, 4)
        if let fps = export.fps, ![24, 25, 30, 50, 60].contains(fps) { throw ValidationError("export.fps \(fps) isn't one of 24, 25, 30, 50, 60") }
    }

    private func checkSpan(_ id: String, take: String, _ start: Double, _ end: Double) throws {
        guard let t = takes[take] else { throw ValidationError("\(id): no take \(take)", hint: takeHint) }
        guard start.isFinite, end.isFinite, start >= -Project.slack, end > start, end <= t.duration + Project.slack else {
            throw ValidationError("\(id): \(fmt(start))–\(fmt(end)) s must be a forward range inside take \(take) (0–\(fmt(t.duration)) s)")
        }
    }

    var takeHint: String { takes.isEmpty ? "the project has no takes yet" : "takes: " + takes.keys.sorted().joined(separator: ", ") }

    private func unit(_ name: String, _ v: Double) throws {
        guard v >= 0 && v <= 1 else { throw ValidationError("\(name) \(v) is outside 0–1 (shares of the screen)") }
    }

    private func range(_ name: String, _ v: Double?, _ lo: Double, _ hi: Double) throws {
        if let v, !(v >= lo && v <= hi) { throw ValidationError("\(name) \(v) is outside \(fmt(lo))–\(fmt(hi))") }
    }
}

/// Seconds for messages: at most 3 decimals, no trailing zeros.
func fmt(_ v: Double) -> String {
    var s = String(format: "%.3f", v)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}

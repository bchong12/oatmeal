import Foundation

/// takes/<id>/take.json: what was recorded and how its files line up. Written when the take starts, refreshed while it
/// rolls (so a crash still leaves a usable record) and finalized at stop.
///
/// Every file in the take starts at the same instant, `hostZero` on the host clock, so file time t is the same moment
/// in screen.mov, system.mov and events.jsonl.
public struct TakeManifest: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case recording, finished, interrupted, failed }

    public struct Source: Codable, Equatable, Sendable {
        /// display | window | region
        public var kind: String
        public var app: String?
        public var bundleID: String?
        public var title: String?
        public var windowID: Int?
        public var displayID: Int?
        /// What was filmed, in global points, top-left origin: [x, y, width, height].
        public var rect: [Double]
        /// Pixels per point of the recording.
        public var pixelScale: Double
        public init(kind: String, app: String? = nil, bundleID: String? = nil, title: String? = nil, windowID: Int? = nil,
                    displayID: Int? = nil, rect: [Double], pixelScale: Double) {
            self.kind = kind; self.app = app; self.bundleID = bundleID; self.title = title; self.windowID = windowID
            self.displayID = displayID; self.rect = rect; self.pixelScale = pixelScale
        }
    }

    public struct Track: Codable, Equatable, Sendable {
        /// screen | system
        public var kind: String
        public var file: String
        public var codec: String?
        public var width: Int?
        public var height: Int?
        public var fps: Double?
        public var frames: Int?
        public var dropped: Int?
        public var sampleRate: Double?
        public var channels: Int?
        /// Seconds of silence written to cover gaps (device switches, pauses).
        public var silenceFilled: Double?
        public var device: String?
        public init(kind: String, file: String) { self.kind = kind; self.file = file }
    }

    /// A stretch of take time; pauses and interruptions become automatic cuts in the project.
    public struct Span: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var reason: String?
        public init(start: Double, end: Double, reason: String? = nil) { self.start = start; self.end = end; self.reason = reason }
    }

    public struct Marker: Codable, Equatable, Sendable {
        public var t: Double
        public var label: String
        public init(t: Double, label: String) { self.t = t; self.label = label }
    }

    public var id: String
    public var name: String
    public var status: Status
    /// ISO 8601 wall time when the take started.
    public var startedAt: String
    /// Host-clock seconds (mach absolute time) at t = 0 of every file.
    public var hostZero: Double
    public var duration: Double
    public var source: Source
    public var tracks: [Track] = []
    /// events.jsonl when input was logged.
    public var events: String?
    public var pauses: [Span] = []
    public var interruptions: [Span] = []
    public var markers: [Marker] = []
    public var warnings: [String] = []
    /// Clock calibration measured at the first frame (diagnostics).
    public var clock: [String: Double] = [:]

    public init(id: String, name: String, status: Status = .recording, startedAt: String, hostZero: Double, duration: Double = 0, source: Source) {
        self.id = id; self.name = name; self.status = status; self.startedAt = startedAt; self.hostZero = hostZero
        self.duration = duration; self.source = source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(.name, or: id)
        status = try c.decode(.status, or: .finished)
        startedAt = try c.decode(.startedAt, or: "")
        hostZero = try c.decode(.hostZero, or: 0)
        duration = try c.decode(.duration, or: 0)
        source = try c.decode(Source.self, forKey: .source)
        tracks = try c.decode(.tracks, or: [])
        events = try c.decodeIfPresent(String.self, forKey: .events)
        pauses = try c.decode(.pauses, or: [])
        interruptions = try c.decode(.interruptions, or: [])
        markers = try c.decode(.markers, or: [])
        warnings = try c.decode(.warnings, or: [])
        clock = try c.decode(.clock, or: [:])
    }

    public func track(_ kind: String) -> Track? { tracks.first { $0.kind == kind } }

    /// The project's summary of this take.
    public var take: Take {
        let screen = track("screen")
        return Take(duration: duration, name: name, width: screen?.width, height: screen?.height, fps: screen?.fps, tracks: tracks.map(\.kind))
    }

    public static let fileName = "take.json"

    public static func load(_ dir: URL) throws -> TakeManifest {
        try LurkerJSON.decoder().decode(TakeManifest.self, from: Data(contentsOf: dir.appending(path: fileName)))
    }

    public func save(to dir: URL) throws {
        var data = try LurkerJSON.encoder().encode(self)
        data.append(0x0A)
        try data.write(to: dir.appending(path: Self.fileName), options: .atomic)
    }
}

extension ProjectDocument {
    /// Adds a recording: registers the take, puts it on the program, and cuts its pauses and interruptions
    /// (marked auto, so a person or agent can restore them).
    @discardableResult
    public mutating func addRecording(_ m: TakeManifest, clip: Bool = true) throws -> EditResult {
        var result = try addTake(m.id, m.take, clip: clip, commit: false)
        let gaps = (m.pauses + m.interruptions).map { (max(0, $0.start), min(m.duration, $0.end)) }.filter { $0.1 - $0.0 >= 0.05 }
        for (a, b) in TimeMap.merged(gaps) {
            let id = result.project.newID("cut")
            result.project.regions.cut.append(Cut(id: id, take: m.id, start: a, end: b, origin: .auto, reason: "recording"))
            result.changes.append("cut \(m.id) \(fmt(a))–\(fmt(b)) s (paused or interrupted)")
        }
        Executor.normalizeCuts(&result.project)
        return try finishAddTake(result, label: "add recording \(m.id)")
    }
}

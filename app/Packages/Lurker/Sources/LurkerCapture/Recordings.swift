import AVFoundation
import Foundation
import LurkerCore

/// Every take in progress, and the projects they record into. A take records into takes/<id>/ of a project bundle;
/// when it stops it is added to the project (pauses and interruptions become automatic cuts).
public final class Recordings: @unchecked Sendable {
    public static let shared = Recordings()

    public struct StartRequest: Codable, Sendable {
        public var source: TargetSpec?
        public var settings: CaptureSettings?
        /// A .lurker project to record into; created if missing. nil = a new project in ~/Movies/Lurker/Projects.
        public var project: String?
        public var name: String?
        public init(source: TargetSpec? = nil, settings: CaptureSettings? = nil, project: String? = nil, name: String? = nil) {
            self.source = source; self.settings = settings; self.project = project; self.name = name
        }
    }

    public struct Active: Sendable {
        public let take: TakeRecorder
        public let project: URL
    }

    private let lock = NSLock()
    private var active: [String: Active] = [:]
    /// Called whenever a take starts or stops (menu bar refresh).
    public var onChange: (@Sendable () -> Void)?

    public static var projectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies/Lurker/Projects", directoryHint: .isDirectory)
    }

    /// In-flight take folders, so a crash can be recovered at the next launch.
    static var inFlightFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Lurker/in-flight.json")
    }

    public var takes: [Active] { lock.withLock { Array(active.values).sorted { $0.take.zero < $1.take.zero } } }

    public func start(_ r: StartRequest) async throws -> [String: Any] {
        let settings = r.settings ?? CaptureSettings()
        let projectURL = try Self.projectURL(r.project, name: r.name)
        if !FileManager.default.fileExists(atPath: projectURL.appending(path: "project.json").path) {
            _ = try ProjectBundle.create(at: projectURL)
        }
        let (bundle, doc) = try ProjectBundle.open(projectURL)
        // reserve an id no other take (finished or rolling) in this project uses
        let id: String = lock.withLock {
            var n = 1
            func taken(_ i: String) -> Bool {
                doc.project.takes[i] != nil || active.values.contains { $0.project == projectURL && $0.take.id == i }
                    || FileManager.default.fileExists(atPath: bundle.takeDirectory(i).path)
            }
            while taken("t\(n)") { n += 1 }
            return "t\(n)"
        }
        let take = try await TakeRecorder.start(r.source ?? TargetSpec(), settings: settings, directory: bundle.takeDirectory(id), id: id, name: r.name)
        take.onAutoStop = { [weak self] t in Task { _ = try? await self?.finish(t) } }
        lock.withLock { active[key(projectURL, id)] = Active(take: take, project: projectURL) }
        saveInFlight()
        onChange?()
        return describe(take, projectURL)
    }

    private func key(_ project: URL, _ id: String) -> String { project.path + "#" + id }

    /// The take to act on: by id, else the newest.
    func find(_ id: String?) throws -> Active {
        let list = takes
        if let id {
            guard let a = list.first(where: { $0.take.id == id || key($0.project, $0.take.id) == id }) else {
                throw CaptureError("no take \(id) is recording" + (list.isEmpty ? "" : "; recording: " + list.map(\.take.id).joined(separator: ", ")))
            }
            return a
        }
        guard let a = list.last else { throw CaptureError("nothing is recording") }
        return a
    }

    public func stop(_ id: String?) async throws -> [[String: Any]] {
        let list = id == nil ? takes : [try find(id)]
        guard !list.isEmpty else { throw CaptureError("nothing is recording") }
        var out: [[String: Any]] = []
        for a in list { out.append(try await finish(a.take)) }
        return out
    }

    /// Stops a take and adds it to its project.
    @discardableResult
    func finish(_ take: TakeRecorder) async throws -> [String: Any] {
        guard let a = lock.withLock({ active.values.first { $0.take === take } }) else { return [:] }
        let manifest = await take.stop()
        lock.withLock { active[key(a.project, take.id)] = nil }
        saveInFlight()
        onChange?()
        var out = Self.summary(manifest)
        out["project"] = a.project.path
        if manifest.status != .failed {
            let r = try Self.addToProject(manifest, a.project)
            out["rev"] = r.rev
            out["clips"] = r.created
        }
        return out
    }

    public static func addToProject(_ m: TakeManifest, _ projectURL: URL) throws -> EditResult {
        let (bundle, doc0) = try ProjectBundle.open(projectURL)
        var doc = doc0
        guard doc.project.takes[m.id] == nil else { return EditResult(rev: doc.project.rev, label: "take \(m.id) already in the project") }
        let r = try doc.addRecording(m)
        try bundle.save(doc)
        try bundle.log(EditBatch(ops: [.note(.init(text: "recorded take \(m.id) (\(String(format: "%.1f", m.duration)) s)"))], label: r.label), r)
        return r
    }

    public func pause(_ id: String?) throws -> [String: Any] { let a = try find(id); try a.take.pause(); return describe(a.take, a.project) }
    public func resume(_ id: String?) throws -> [String: Any] { let a = try find(id); try a.take.resume(); return describe(a.take, a.project) }
    public func mark(_ label: String, _ id: String?) throws -> [String: Any] {
        let a = try find(id)
        let m = a.take.mark(label)
        return ["take": a.take.id, "t": m.t, "label": m.label]
    }
    public func status() -> [[String: Any]] { takes.map { describe($0.take, $0.project) } }

    public func simulateInterruption(_ id: String?, locked: Bool? = nil) async throws -> [String: Any] {
        let a = try find(id)
        if let locked { await a.take.simulateLock(locked) } else { await a.take.simulateInterruption() }
        return describe(a.take, a.project)
    }

    func describe(_ t: TakeRecorder, _ project: URL) -> [String: Any] {
        var d: [String: Any] = ["take": t.id, "project": project.path, "state": t.currentState.rawValue,
                                "elapsed": (t.elapsed * 10).rounded() / 10, "source": t.target.manifestSource.kind,
                                "app": t.target.app, "title": t.target.title]
        for (k, v) in t.counters { d[k] = v }
        return d
    }

    static func summary(_ m: TakeManifest) -> [String: Any] {
        var d: [String: Any] = ["take": m.id, "status": m.status.rawValue, "duration": (m.duration * 100).rounded() / 100,
                                "tracks": m.tracks.map(\.kind), "markers": m.markers.count]
        if !m.pauses.isEmpty { d["pauses"] = m.pauses.count }
        if !m.interruptions.isEmpty { d["interruptions"] = m.interruptions.map { ["start": $0.start, "end": $0.end, "reason": $0.reason ?? ""] } }
        if !m.warnings.isEmpty { d["warnings"] = m.warnings }
        if let s = m.track("screen") { d["frames"] = s.frames ?? 0; d["dropped"] = s.dropped ?? 0; d["size"] = "\(s.width ?? 0)x\(s.height ?? 0)" }
        return d
    }

    static func projectURL(_ path: String?, name: String?) throws -> URL {
        if let path, !path.isEmpty {
            var url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            if url.pathExtension != "lurker" { url = url.appendingPathExtension("lurker") }
            return url
        }
        try FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"
        let slug = String((name ?? "take").lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }).split(separator: "-").joined(separator: "-")
        return projectsDirectory.appending(path: "\(slug.isEmpty ? "take" : String(slug.prefix(40)))-\(f.string(from: Date())).lurker", directoryHint: .isDirectory)
    }

    // MARK: crash recovery

    private func saveInFlight() {
        let dirs = takes.map { $0.project.appending(path: "takes/\($0.take.id)").path }
        try? FileManager.default.createDirectory(at: Self.inFlightFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: dirs).write(to: Self.inFlightFile, options: .atomic)
    }

    /// After a crash: takes that were rolling get their real length from the files, are marked interrupted and are
    /// added to their projects. Call once at launch.
    public func recoverAfterCrash() async -> [[String: Any]] {
        guard let data = try? Data(contentsOf: Self.inFlightFile), let dirs = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        var out: [[String: Any]] = []
        for path in dirs {
            let dir = URL(fileURLWithPath: path, isDirectory: true)
            guard let r = try? await Self.recover(dir) else { continue }
            out.append(r)
        }
        try? FileManager.default.removeItem(at: Self.inFlightFile)
        return out
    }

    /// Rebuilds a take whose app died mid-recording from what made it to disk.
    public static func recover(_ dir: URL) async throws -> [String: Any] {
        var m = try TakeManifest.load(dir)
        guard m.status == .recording else { return ["take": m.id, "status": m.status.rawValue, "recovered": false] }
        var tracks: [TakeManifest.Track] = []
        var longest = 0.0
        for (kind, file) in [("screen", "screen.mov"), ("system", "system.mov")] {
            let url = dir.appending(path: file)
            guard FileManager.default.fileExists(atPath: url.path),
                  let duration = try? await AVURLAsset(url: url).load(.duration).seconds, duration > 0 else { continue }
            var t = m.track(kind) ?? TakeManifest.Track(kind: kind, file: file)
            if kind == "screen",
               let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first {
                let size = try? await track.load(.naturalSize)
                t.width = size.map { Int($0.width) }; t.height = size.map { Int($0.height) }
            }
            tracks.append(t)
            longest = max(longest, duration)
        }
        m.tracks = tracks
        m.duration = longest
        m.status = tracks.contains { $0.kind == "screen" } ? .interrupted : .failed
        m.warnings.append("recovered after Lurker quit unexpectedly; kept \(String(format: "%.1f", longest)) s")
        try m.save(to: dir)
        var out = summary(m)
        let project = dir.deletingLastPathComponent().deletingLastPathComponent()
        if m.status == .interrupted, let r = try? addToProject(m, project) { out["rev"] = r.rev }
        out["project"] = project.path
        out["recovered"] = true
        return out
    }
}

import Foundation
import LurkerCore

/// Background work (exports, analysis) that outlives the call that started it. Callers poll by id.
public final class Jobs: @unchecked Sendable {
    public static let shared = Jobs()

    public struct Job: Sendable {
        public let id: String
        public let kind: String
        public let project: String
        public var status: String = "running"
        public var progress: Double = 0
        public var result: [String: String] = [:]
        public var error: String?
        public let started = Date()
        public var finished: Date?

        public var dictionary: [String: Any] {
            var d: [String: Any] = ["id": id, "kind": kind, "project": project, "status": status, "progress": (progress * 100).rounded() / 100,
                                    "seconds": ((finished ?? Date()).timeIntervalSince(started) * 10).rounded() / 10]
            if !result.isEmpty { d["result"] = result }
            if let error { d["error"] = error }
            return d
        }
    }

    private let lock = NSLock()
    private var jobs: [String: Job] = [:]
    private var cancels: [String: @Sendable () -> Void] = [:]
    /// Finished exports by (project, rev, preset, options): asking again returns the same file.
    private var cache: [String: String] = [:]

    public func job(_ id: String) -> Job? { lock.withLock { jobs[id] } }
    public var all: [Job] { lock.withLock { jobs.values.sorted { $0.started > $1.started } } }

    func update(_ id: String, _ f: (inout Job) -> Void) { lock.withLock { if var j = jobs[id] { f(&j); jobs[id] = j } } }

    public func cancel(_ id: String) throws {
        guard let c = lock.withLock({ cancels[id] }) else { throw EngineError("no running job \(id)") }
        c()
    }

    /// Starts an export and returns at once. Identical requests for an unchanged project reuse the finished file.
    public func export(_ bundle: ProjectBundle, preset: ExportSettings.Preset, out: URL?, resolution: ExportSettings.Resolution?, fps: Double?) throws -> Job {
        let (_, doc) = try ProjectBundle.open(bundle.url)
        let key = "\(bundle.url.path)#\(doc.project.rev)#\(preset.rawValue)#\(resolution?.rawValue ?? "")#\(fps ?? 0)#\(out?.path ?? "")"
        let id = "x" + String(UUID().uuidString.prefix(7)).lowercased()
        if let path = lock.withLock({ cache[key] }), FileManager.default.fileExists(atPath: path) {
            var j = Job(id: id, kind: "export", project: bundle.url.path)
            j.status = "done"; j.progress = 1; j.result = ["output": path, "cached": "true"]; j.finished = Date()
            lock.withLock { jobs[id] = j }
            return j
        }
        let p = ExportPreset.named(preset)
        let ext = p.gif ? "gif" : (p.fileType == .mov ? "mov" : "mp4")
        let name = bundle.url.deletingPathExtension().lastPathComponent
        let target = out ?? bundle.url.deletingLastPathComponent().appending(path: "\(name)-\(preset.rawValue)-r\(doc.project.rev).\(ext)")
        let exporter = Exporter()
        let job = Job(id: id, kind: "export", project: bundle.url.path)
        lock.withLock { jobs[id] = job; cancels[id] = { exporter.cancel() } }
        let project = doc.project
        Task.detached(priority: .utility) { [self] in
            do {
                let r = try await exporter.export(bundle: bundle, project: project, preset: p, to: target, resolution: resolution, fps: fps) { prog in
                    self.update(id) { $0.progress = prog }
                }
                update(id) {
                    $0.status = "done"; $0.progress = 1; $0.finished = Date()
                    $0.result = ["output": r.output, "width": "\(r.width)", "height": "\(r.height)", "fps": "\(r.fps)", "frames": "\(r.frames)",
                                 "duration": String(format: "%.2f", r.duration), "sizeMB": "\(r.sizeMB)", "renderSeconds": "\(r.seconds)", "rev": "\(project.rev)"]
                }
                lock.withLock { cache[key] = r.output }
            } catch {
                update(id) { $0.status = "error"; $0.error = "\(error)"; $0.finished = Date() }
            }
            _ = lock.withLock { cancels.removeValue(forKey: id) }
        }
        return job
    }

    /// Waits up to `seconds` for a job to finish (long-poll), returning its state either way.
    public func wait(_ id: String, seconds: Double) async throws -> Job {
        let until = Date().addingTimeInterval(min(max(0, seconds), 55))
        while true {
            guard let j = job(id) else { throw EngineError("no job \(id)") }
            if j.status != "running" || Date() >= until { return j }
            try await Task.sleep(for: .milliseconds(250))
        }
    }
}

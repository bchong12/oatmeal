import Foundation

/// A project on disk: a folder package.
///
///     Demo.lurker/
///       project.json                 the document
///       takes/<id>/                  media and logs per recording
///       derived/                     regenerable analysis (transcripts, waveforms, thumbnails, proxies)
///       history/journal.jsonl        every applied batch, one per line
///       history/checkpoints/<n>.json named snapshots
public struct ProjectBundle: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public var projectFile: URL { url.appending(path: "project.json") }
    public var takesDirectory: URL { url.appending(path: "takes", directoryHint: .isDirectory) }
    public var derivedDirectory: URL { url.appending(path: "derived", directoryHint: .isDirectory) }
    public var historyDirectory: URL { url.appending(path: "history", directoryHint: .isDirectory) }
    var checkpointsDirectory: URL { historyDirectory.appending(path: "checkpoints", directoryHint: .isDirectory) }
    var journalFile: URL { historyDirectory.appending(path: "journal.jsonl") }

    public func takeDirectory(_ id: String) -> URL { takesDirectory.appending(path: id, directoryHint: .isDirectory) }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
        init(_ d: String) { description = d }
    }

    /// Makes a new bundle. Refuses to touch anything that already exists.
    public static func create(at url: URL, project: Project = Project()) throws -> ProjectBundle {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw Failure("\(url.path) already exists") }
        let b = ProjectBundle(url: url)
        for dir in [b.takesDirectory, b.derivedDirectory, b.checkpointsDirectory] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try b.write(project, to: b.projectFile)
        return b
    }

    /// Opens a bundle with its checkpoints. The undo history starts empty; the journal keeps the record.
    public static func open(_ url: URL) throws -> (ProjectBundle, ProjectDocument) {
        let b = ProjectBundle(url: url)
        guard FileManager.default.fileExists(atPath: b.projectFile.path) else { throw Failure("\(url.path) isn't a Lurker project (no project.json)") }
        let project: Project
        do { project = try LurkerJSON.decoder().decode(Project.self, from: Data(contentsOf: b.projectFile)) }
        catch { throw Failure("project.json: \(LurkerJSON.describe(error))") }
        do { try project.validate() } catch { throw Failure("project.json: \(error)") }
        var checkpoints: [String: Project] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: b.checkpointsDirectory, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "json" {
            if let p = try? LurkerJSON.decoder().decode(Project.self, from: Data(contentsOf: f)) {
                checkpoints[f.deletingPathExtension().lastPathComponent] = p
            }
        }
        return (b, ProjectDocument(project, checkpoints: checkpoints))
    }

    /// Writes project.json atomically (a crash leaves the old or the new file, never half of one) and syncs checkpoints.
    public func save(_ doc: ProjectDocument) throws {
        try write(doc.project, to: projectFile)
        try FileManager.default.createDirectory(at: checkpointsDirectory, withIntermediateDirectories: true)
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: checkpointsDirectory.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) })
        for (name, p) in doc.checkpoints { try write(p, to: checkpointsDirectory.appending(path: "\(name).json")) }
        for gone in existing.subtracting(doc.checkpoints.keys) {
            try? FileManager.default.removeItem(at: checkpointsDirectory.appending(path: "\(gone).json"))
        }
    }

    /// Appends one applied batch to the journal: when, which rev it made, and the ops as sent.
    public func log(_ batch: EditBatch, _ result: EditResult, at date: Date = Date()) throws {
        struct Line: Encodable { let at: String; let rev: Int; let label: String; let ops: [Op]; let created: [String] }
        var data = try LurkerJSON.lineEncoder().encode(Line(at: date.ISO8601Format(), rev: result.rev, label: result.label, ops: batch.ops, created: result.created))
        data.append(0x0A)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: journalFile.path) {
            try data.write(to: journalFile)
            return
        }
        let h = try FileHandle(forWritingTo: journalFile)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: data)
    }

    func write(_ project: Project, to file: URL) throws {
        var data = try LurkerJSON.encoder().encode(project)
        data.append(0x0A)
        try data.write(to: file, options: .atomic)
    }
}

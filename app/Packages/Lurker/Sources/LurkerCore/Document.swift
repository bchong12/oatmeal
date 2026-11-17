import Foundation

/// A project plus its edit history. Every change goes through here: ops, undo, redo, checkpoints, new takes.
public struct ProjectDocument: Sendable {
    public private(set) var project: Project
    /// Named snapshots an agent can return to ("before-zooms").
    public private(set) var checkpoints: [String: Project] = [:]

    struct Entry: Sendable { let label: String; let before: Project }
    private var undoStack: [Entry] = []
    private var redoStack: [Entry] = []
    static let historyLimit = 200

    public init(_ project: Project = Project(), checkpoints: [String: Project] = [:]) {
        self.project = project
        self.checkpoints = checkpoints
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoLabel: String? { undoStack.last?.label }
    public var redoLabel: String? { redoStack.last?.label }
    public var timeMap: TimeMap { TimeMap(project) }

    /// Applies a batch atomically: all ops land as one undo step, or none do.
    @discardableResult
    public mutating func apply(_ batch: EditBatch) throws -> EditResult {
        if let base = batch.baseRev, base != project.rev {
            throw EditError("baseRev \(base) is stale; the project is at rev \(project.rev)", hint: "read the project again, then resend against rev \(project.rev)")
        }
        guard !batch.ops.isEmpty else { throw EditError("ops is empty") }
        let out = try Executor.run(batch.ops, timebase: batch.timebase ?? .source, on: project)
        let label = batch.label ?? Self.label(batch.ops)
        var result = EditResult(rev: project.rev, label: label, created: out.created, changes: out.changes, dryRun: batch.dryRun ?? false)
        if result.dryRun { return result }
        if Self.sameContent(out.project, project) { return result }
        commit(out.project, label: label)
        result.rev = project.rev
        return result
    }

    /// The project a batch would produce, without keeping it (previews of an edit before committing).
    public func preview(_ batch: EditBatch) throws -> Project {
        try Executor.run(batch.ops, timebase: batch.timebase ?? .source, on: project).project
    }

    @discardableResult
    public mutating func undo() throws -> EditResult {
        guard let entry = undoStack.popLast() else { throw EditError("nothing to undo") }
        redoStack.append(Entry(label: entry.label, before: project))
        replace(with: entry.before)
        return EditResult(rev: project.rev, label: "undo \(entry.label)")
    }

    @discardableResult
    public mutating func redo() throws -> EditResult {
        guard let entry = redoStack.popLast() else { throw EditError("nothing to redo") }
        undoStack.append(Entry(label: entry.label, before: project))
        replace(with: entry.before)
        return EditResult(rev: project.rev, label: "redo \(entry.label)")
    }

    /// Brings back the content of an earlier rev from the undo history, as a new undoable change.
    @discardableResult
    public mutating func revert(to rev: Int) throws -> EditResult {
        guard rev != project.rev else { return EditResult(rev: rev, label: "already at rev \(rev)") }
        guard let entry = undoStack.last(where: { $0.before.rev == rev }) else {
            let revs = undoStack.map { String($0.before.rev) }.suffix(20).joined(separator: ", ")
            throw EditError("rev \(rev) isn't in the undo history", hint: revs.isEmpty ? "there is no history yet" : "revs: \(revs)")
        }
        commit(entry.before, label: "revert to rev \(rev)")
        return EditResult(rev: project.rev, label: "revert to rev \(rev)")
    }

    public mutating func checkpoint(_ name: String) throws {
        guard Self.validName(name) else { throw EditError("checkpoint names use letters, digits, - and _ (up to 64)") }
        checkpoints[name] = project
    }

    @discardableResult
    public mutating func restore(checkpoint name: String) throws -> EditResult {
        guard let saved = checkpoints[name] else {
            throw EditError("no checkpoint \(name)", hint: checkpoints.isEmpty ? "none saved" : "checkpoints: " + checkpoints.keys.sorted().joined(separator: ", "))
        }
        commit(saved, label: "restore checkpoint \(name)")
        return EditResult(rev: project.rev, label: "restore checkpoint \(name)")
    }

    /// Registers a finished recording, and by default puts all of it at the end of the program.
    @discardableResult
    public mutating func addTake(_ id: String, _ take: Take, clip: Bool = true) throws -> EditResult {
        try finishAddTake(try addTake(id, take, clip: clip, commit: false), label: "add take \(id)")
    }

    /// The next free take id: t1, t2, …
    public var nextTakeID: String {
        var n = 1
        while project.takes["t\(n)"] != nil { n += 1 }
        return "t\(n)"
    }

    struct PendingTake { var project: Project; var created: [String]; var changes: [String] }

    func addTake(_ id: String, _ take: Take, clip: Bool, commit: Bool) throws -> PendingTake {
        guard Self.validName(id) else { throw EditError("take ids use letters, digits, - and _ (up to 64)") }
        guard project.takes[id] == nil else { throw EditError("take \(id) already exists") }
        var next = project
        next.takes[id] = take
        var created: [String] = []
        if clip {
            let cid = next.newID("clip")
            next.clips.append(Clip(id: cid, take: id, start: 0, end: take.duration))
            created.append(cid)
        }
        return PendingTake(project: next, created: created, changes: ["take \(id): \(fmt(take.duration)) s"])
    }

    mutating func finishAddTake(_ pending: PendingTake, label: String) throws -> EditResult {
        do { try pending.project.validate() } catch let e as ValidationError { throw EditError(e.message, hint: e.hint) }
        commit(pending.project, label: label)
        return EditResult(rev: project.rev, label: label, created: pending.created, changes: pending.changes)
    }

    /// Swaps a take's automatic regions for freshly planned ones, as one undoable change. Manual regions are never
    /// touched; planned speed-ups and cuts that would overlap manual ones are dropped.
    @discardableResult
    public mutating func replaceAutoRegions(take: String, zooms: [Zoom]? = nil, speeds: [Speed]? = nil, cuts: [Cut]? = nil, cutReasons: Set<String>? = nil,
                                            label: String) throws -> EditResult {
        guard project.takes[take] != nil else { throw EditError("no take \(take)", hint: project.takeHint) }
        var next = project
        var created: [String] = []
        var changes: [String] = []
        func overlapsManual<R: Region>(_ list: [R], _ r: R) -> Bool {
            list.contains { $0.take == take && $0.origin != .auto && $0.start < r.end && r.start < $0.end }
        }
        if let zooms {
            let before = next.regions.zoom.count
            next.regions.zoom.removeAll { $0.take == take && $0.origin == .auto }
            let manual = next.regions.zoom
            for var z in zooms where !manual.contains(where: { $0.take == take && $0.start < z.end && z.start < $0.end }) {
                z.id = next.newID("zoom"); z.take = take; z.origin = .auto
                next.regions.zoom.append(z); created.append(z.id)
            }
            next.regions.zoom.sort(by: Regions.order)
            changes.append("auto zooms: \(before - manual.count) → \(next.regions.zoom.count - manual.count)")
        }
        if let speeds {
            next.regions.speed.removeAll { $0.take == take && $0.origin == .auto }
            let existing = next.regions.speed
            for var s in speeds where !overlapsManual(existing, s) && !existing.contains(where: { $0.take == take && $0.start < s.end && s.start < $0.end }) {
                s.id = next.newID("speed"); s.take = take; s.origin = .auto
                next.regions.speed.append(s); created.append(s.id)
            }
            next.regions.speed.sort(by: Regions.order)
            changes.append("auto speed-ups: \(speeds.count) planned")
        }
        if let cuts {
            // only the automatic cuts of the kinds being re-planned (fillers, pauses…) are replaced
            next.regions.cut.removeAll { $0.take == take && $0.origin == .auto && (cutReasons == nil || cutReasons!.contains($0.reason ?? "")) }
            let existing = next.regions.cut
            for var c in cuts where !overlapsManual(existing, c) {
                c.id = next.newID("cut"); c.take = take; c.origin = .auto
                next.regions.cut.append(c); created.append(c.id)
            }
            Executor.normalizeCuts(&next)
            changes.append("auto cuts: \(cuts.count) planned")
        }
        do { try next.validate() } catch let e as ValidationError { throw EditError(e.message, hint: e.hint) }
        if Self.sameContent(next, project) { return EditResult(rev: project.rev, label: label, changes: ["no change"]) }
        commit(next, label: label)
        return EditResult(rev: project.rev, label: label, created: created, changes: changes)
    }

    // MARK: internals

    private mutating func commit(_ next: Project, label: String) {
        undoStack.append(Entry(label: label, before: project))
        if undoStack.count > Self.historyLimit { undoStack.removeFirst(undoStack.count - Self.historyLimit) }
        redoStack.removeAll()
        replace(with: next)
    }

    /// Swaps in content as a new rev. The id serial never goes back, so undone ids aren't handed out again.
    private mutating func replace(with content: Project) {
        var p = content
        p.rev = project.rev + 1
        p.serial = max(p.serial, project.serial)
        project = p
    }

    static func sameContent(_ a: Project, _ b: Project) -> Bool {
        var a = a, b = b
        a.rev = 0; b.rev = 0; a.serial = 0; b.serial = 0
        return a == b
    }

    static func validName(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 64 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    static func label(_ ops: [Op]) -> String {
        let names = ops.map(\.name)
        var counts: [(String, Int)] = []
        for n in names {
            if let i = counts.firstIndex(where: { $0.0 == n }) { counts[i].1 += 1 } else { counts.append((n, 1)) }
        }
        return counts.map { $0.1 > 1 ? "\($0.0) ×\($0.1)" : $0.0 }.joined(separator: ", ")
    }
}

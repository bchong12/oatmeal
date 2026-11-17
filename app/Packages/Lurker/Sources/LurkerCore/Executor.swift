import Foundation

/// A refused edit. `op` is the index of the op that failed; nothing in the batch was applied.
public struct EditError: LocalizedError, Equatable, CustomStringConvertible {
    public var op: Int?
    public var message: String
    public var hint: String?

    public init(_ message: String, hint: String? = nil, op: Int? = nil) { self.message = message; self.hint = hint; self.op = op }

    public var errorDescription: String? { description }

    public var description: String {
        var s = op.map { "op \($0): \(message)" } ?? message
        if let hint { s += " — \(hint)" }
        return s
    }
}

public struct EditResult: Codable, Equatable, Sendable {
    public var rev: Int
    public var label: String
    /// Ids of clips and regions the batch made, in op order.
    public var created: [String] = []
    /// One readable line per change.
    public var changes: [String] = []
    public var dryRun = false

    public init(rev: Int, label: String, created: [String] = [], changes: [String] = [], dryRun: Bool = false) {
        self.rev = rev; self.label = label; self.created = created; self.changes = changes; self.dryRun = dryRun
    }
}

/// Applies ops to a copy of a project. Pure: the same ops on the same project always give the same result.
enum Executor {
    struct Outcome {
        var project: Project
        var created: [String] = []
        var changes: [String] = []
    }

    static func run(_ ops: [Op], timebase: Timebase, on start: Project) throws -> Outcome {
        var out = Outcome(project: start)
        for (i, op) in ops.enumerated() {
            do {
                try apply(op, timebase, &out)
                try out.project.validate()
            } catch var e as EditError {
                e.op = i; throw e
            } catch let e as ValidationError {
                throw EditError(e.message, hint: e.hint, op: i)
            } catch {
                throw EditError(LurkerJSON.describe(error), op: i)
            }
        }
        return out
    }

    // MARK: ops

    static func apply(_ op: Op, _ tb: Timebase, _ out: inout Outcome) throws {
        switch op {
        case .addClip(let a):
            guard let take = out.project.takes[a.take] else { throw EditError("no take \(a.take)", hint: out.project.takeHint) }
            let id = out.project.newID("clip")
            let clip = Clip(id: id, take: a.take, start: a.start ?? 0, end: a.end ?? take.duration)
            let at = a.at ?? out.project.clips.count
            guard (0...out.project.clips.count).contains(at) else { throw EditError("at \(at) is outside 0–\(out.project.clips.count)") }
            out.project.clips.insert(clip, at: at)
            out.created.append(id)
            out.changes.append("\(id): \(a.take) \(fmt(clip.start))–\(fmt(clip.end)) s at position \(at)")

        case .moveClip(let m):
            guard let i = out.project.clips.firstIndex(where: { $0.id == m.id }) else { throw missing(m.id, out.project) }
            guard (0..<out.project.clips.count).contains(m.to) else { throw EditError("to \(m.to) is outside 0–\(out.project.clips.count - 1)") }
            out.project.clips.insert(out.project.clips.remove(at: i), at: m.to)
            out.changes.append("\(m.id) moved to position \(m.to)")

        case .trimClip(let t):
            guard let i = out.project.clips.firstIndex(where: { $0.id == t.id }) else { throw missing(t.id, out.project) }
            guard t.start != nil || t.end != nil else { throw EditError("give start, end or both") }
            if let s = t.start { out.project.clips[i].start = s }
            if let e = t.end { out.project.clips[i].end = e }
            let c = out.project.clips[i]
            out.changes.append("\(c.id) now \(fmt(c.start))–\(fmt(c.end)) s of \(c.take)")

        case .cut(let s):
            for r in try ranges(s.take, s.start, s.end, tb, out.project) {
                let id = out.project.newID("cut")
                out.project.regions.cut.append(Cut(id: id, take: r.take, start: r.start, end: r.end))
                normalizeCuts(&out.project)
                let kept = out.project.regions.cut.first { $0.take == r.take && $0.start <= r.start + TimeMap.epsilon && $0.end >= r.end - TimeMap.epsilon }
                if let kept, !out.created.contains(kept.id) { out.created.append(kept.id) }
                out.changes.append("cut \(r.take) \(fmt(r.start))–\(fmt(r.end)) s" + (kept.map { $0.id != id ? " (joined \($0.id))" : "" } ?? ""))
            }

        case .restore(let s):
            for r in try ranges(s.take, s.start, s.end, tb, out.project) {
                var cuts = out.project.regions.cut
                cuts = carve(cuts, take: r.take, r.start, r.end) { out.project.newID("cut") }
                out.project.regions.cut = cuts
                out.changes.append("restored \(r.take) \(fmt(r.start))–\(fmt(r.end)) s")
            }

        case .setSpeed(let s):
            guard s.rate >= 1.0 / 32 && s.rate <= 32 else { throw EditError("rate \(s.rate) is outside 1/32–32", hint: "2 = twice as fast, 0.5 = half speed, 1 = normal") }
            for r in try ranges(s.take, s.start, s.end, tb, out.project) {
                var speeds = out.project.regions.speed
                speeds = carve(speeds, take: r.take, r.start, r.end) { out.project.newID("speed") }
                if abs(s.rate - 1) > 1e-9 {
                    let id = out.project.newID("speed")
                    speeds.append(Speed(id: id, take: r.take, start: r.start, end: r.end, rate: s.rate, audio: s.audio))
                    out.created.append(id)
                }
                out.project.regions.speed = speeds.sorted(by: Regions.order)
                out.changes.append("\(r.take) \(fmt(r.start))–\(fmt(r.end)) s at \(fmt(s.rate))×")
            }

        case .addZoom(let z):
            let r = try single(z.take, z.start, z.end, tb, out.project)
            let id = out.project.newID("zoom")
            out.project.regions.zoom.append(Zoom(id: id, take: r.take, start: r.start, end: r.end, depth: z.depth ?? 2, x: z.x, y: z.y, instant: z.instant))
            out.project.regions.zoom.sort(by: Regions.order)
            out.created.append(id)
            out.changes.append("\(id): \(fmt(z.depth ?? 2))× on \(r.take) \(fmt(r.start))–\(fmt(r.end)) s" + (z.x.map { " at \(fmt($0)), \(fmt(z.y ?? 0))" } ?? " following the action"))

        case .addMask(let m):
            let r = try single(m.take, m.start, m.end, tb, out.project)
            let id = out.project.newID("mask")
            out.project.regions.mask.append(Mask(id: id, take: r.take, start: r.start, end: r.end, effect: m.effect ?? .blur, rect: m.rect, track: m.track))
            out.project.regions.mask.sort(by: Regions.order)
            out.created.append(id)
            out.changes.append("\(id): \((m.effect ?? .blur).rawValue) on \(r.take) \(fmt(r.start))–\(fmt(r.end)) s")

        case .update(let u):
            guard let kind = out.project.regions.kind(of: u.id), case .object(var fields)? = try out.project.regions.json(of: u.id) else {
                if out.project.clips.contains(where: { $0.id == u.id }) { throw EditError("\(u.id) is a clip", hint: "use trim_clip or move_clip") }
                throw missing(u.id, out.project)
            }
            let allowed = Regions.fields(kind)
            for (key, value) in u.fields {
                guard key != "id", key != "take" else { throw EditError("\(key) can't change", hint: "remove the region and add a new one") }
                guard allowed.contains(key) else { throw EditError("\(kind.rawValue) has no field \(key)", hint: "fields: " + allowed.joined(separator: ", ")) }
                if value == .null { fields.removeValue(forKey: key) } else { fields[key] = value }
            }
            // a person or agent touched it, so planners must leave it alone
            fields.removeValue(forKey: "origin")
            try out.project.regions.replace(u.id, with: .object(fields))
            if kind == .cut { normalizeCuts(&out.project) }
            out.changes.append("\(u.id): " + u.fields.keys.sorted().map { "\($0) = \(short(u.fields[$0]!))" }.joined(separator: ", "))

        case .remove(let t):
            if let i = out.project.clips.firstIndex(where: { $0.id == t.id }) {
                out.project.clips.remove(at: i)
            } else if !out.project.regions.remove(t.id) {
                throw missing(t.id, out.project)
            }
            out.changes.append("removed \(t.id)")

        case .set(let s):
            let path = s.path.split(separator: ".").map(String.init)
            guard let root = path.first, Project.settingsRoots.contains(root), path.count >= 2 else {
                throw EditError("can't set \(s.path)", hint: "paths start with " + Project.settingsRoots.joined(separator: ", ") + ", e.g. canvas.padding")
            }
            let json = try JSONValue.from(out.project).setting(path, to: s.value)
            let next = try json.decode(Project.self)
            // unknown keys decode silently; catch typos by looking for the value after a round trip
            if s.value != .null, try JSONValue.from(next).value(at: path) == nil {
                let keys = Mirror(reflecting: settingsSample(root)).children.compactMap(\.label)
                throw EditError("\(root) has no setting \(path.dropFirst().joined(separator: "."))", hint: "\(root): " + keys.joined(separator: ", "))
            }
            out.project = next
            out.changes.append(s.value == .null ? "\(s.path) reset to default" : "\(s.path) = \(short(s.value))")

        case .note(let n):
            out.changes.append("note: \(n.text)")
        }
    }

    // MARK: helpers

    static func missing(_ id: String, _ p: Project) -> EditError {
        let ids = p.allIDs
        return EditError("no clip or region \(id)", hint: ids.isEmpty ? "the project has no clips or regions" : "ids: " + ids.prefix(30).joined(separator: ", ") + (ids.count > 30 ? ", …" : ""))
    }

    static func take(_ take: String?, _ p: Project) throws -> String {
        if let take {
            guard p.takes[take] != nil else { throw EditError("no take \(take)", hint: p.takeHint) }
            return take
        }
        if let only = p.soleTake { return only }
        throw EditError("take is required", hint: p.takeHint + "; or send timebase program")
    }

    /// The source stretches an op covers. Program spans can cross cuts and clips.
    static func ranges(_ takeID: String?, _ start: Double, _ end: Double, _ tb: Timebase, _ p: Project) throws -> [TimeMap.SourceRange] {
        guard start.isFinite, end.isFinite, end > start else { throw EditError("end (\(fmt(end))) must be after start (\(fmt(start)))") }
        switch tb {
        case .source:
            return [.init(take: try take(takeID, p), start: start, end: end)]
        case .program:
            guard takeID == nil else { throw EditError("take only applies to source times", hint: "drop take, or send timebase source") }
            let map = TimeMap(p)
            let r = map.sourceRanges(from: start, to: end)
            guard !r.isEmpty else { throw EditError("\(fmt(start))–\(fmt(end)) s is outside the program (0–\(fmt(map.duration)) s)") }
            return r
        }
    }

    /// One stretch for a region. A program span that crosses cuts inside one clip becomes its outer bounds,
    /// since the cut material never shows.
    static func single(_ takeID: String?, _ start: Double, _ end: Double, _ tb: Timebase, _ p: Project) throws -> TimeMap.SourceRange {
        let r = try ranges(takeID, start, end, tb, p)
        guard let first = r.first, let last = r.last else { throw EditError("empty range") }
        guard r.allSatisfy({ $0.clip == first.clip && $0.take == first.take }), last.end > first.start else {
            throw EditError("\(fmt(start))–\(fmt(end)) s spans more than one clip", hint: "send one op per clip")
        }
        return .init(take: first.take, start: first.start, end: last.end, clip: first.clip)
    }

    /// Removes start..<end from one take's regions, splitting any that straddle it; the right part gets a new id.
    static func carve<R: Region>(_ list: [R], take: String, _ start: Double, _ end: Double, newID: () -> String) -> [R] {
        var out: [R] = []
        for r in list {
            guard r.take == take, r.end > start, r.start < end else { out.append(r); continue }
            if start - r.start >= TimeMap.epsilon { var left = r; left.end = start; out.append(left) }
            if r.end - end >= TimeMap.epsilon { var right = r; right.start = end; if r.start < start - TimeMap.epsilon { right.id = newID() }; out.append(right) }
        }
        return out.sorted(by: Regions.order)
    }

    /// Joins overlapping or touching cuts per take; the earliest keeps its id.
    static func normalizeCuts(_ p: inout Project) {
        var out: [Cut] = []
        for c in p.regions.cut.sorted(by: Regions.order) {
            if let last = out.last, last.take == c.take, c.start <= last.end + TimeMap.epsilon {
                out[out.count - 1].end = max(last.end, c.end)
                if c.origin != .auto { out[out.count - 1].origin = nil; out[out.count - 1].reason = c.reason ?? last.reason }
            } else {
                out.append(c)
            }
        }
        p.regions.cut = out
    }

    static func settingsSample(_ root: String) -> Any {
        switch root {
        case "canvas": Canvas()
        case "cursor": CursorStyle()
        case "audio": AudioStyle()
        default: ExportSettings()
        }
    }

    static func short(_ v: JSONValue) -> String {
        switch v {
        case .null: "null"
        case .bool(let b): "\(b)"
        case .number(let n): fmt(n)
        case .string(let s): "\"\(s)\""
        case .array, .object: (try? String(decoding: LurkerJSON.lineEncoder().encode(v), as: UTF8.self)) ?? "…"
        }
    }
}

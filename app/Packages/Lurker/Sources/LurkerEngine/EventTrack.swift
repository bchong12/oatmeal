import CoreGraphics
import Foundation

/// A take's events.jsonl, parsed and moved into source pixels (the screen file's pixels, top-left origin).
/// Window takes follow the window: a point is placed by where it sits inside the window's frame at that moment.
public struct EventTrack: Sendable {
    public struct Sample: Sendable, Equatable { public let t: Double; public let x: Double; public let y: Double }
    public struct Click: Sendable, Equatable { public let t: Double; public let x: Double; public let y: Double; public let button: String; public let up: Double? }
    public struct Key: Sendable, Equatable { public let t: Double; public let chars: String; public let mods: [String] }
    public struct Shape: Sendable, Equatable { public let id: String; public let hotX: Double; public let hotY: Double; public let width: Double; public let height: Double }

    /// Moves, drags and button positions, sorted by time.
    public private(set) var moves: [Sample] = []
    public private(set) var clicks: [Click] = []
    public private(set) var scrolls: [Double] = []
    /// Scroll amounts (points, NSEvent sign: negative = content moves up), with their times.
    public private(set) var scrollDeltas: [(t: Double, dy: Double)] = []
    public private(set) var keys: [Key] = []
    /// (time, cursor id) changes.
    public private(set) var cursors: [(Double, String)] = []
    public private(set) var shapes: [String: Shape] = [:]
    public private(set) var markers: [(Double, String)] = []
    /// Elements an agent acted on (from the drive log), in source pixels.
    public private(set) var targets: [(t: Double, rect: CGRect)] = []
    /// The agent drove a virtual cursor; its path is already human-like.
    public private(set) var virtual = false
    /// Source pixels per point.
    public private(set) var scale = 2.0

    public init() {}

    public static func load(_ url: URL, sourceSize: CGSize) -> EventTrack {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return EventTrack() }
        return parse(text, sourceSize: sourceSize)
    }

    public static func parse(_ text: String, sourceSize: CGSize) -> EventTrack {
        var e = EventTrack()
        var frames: [(Double, CGRect)] = []
        var raw: [(t: Double, type: String, x: Double, y: Double, button: String)] = []
        var targetRows: [(Double, CGRect)] = []
        for line in text.split(separator: "\n") {
            guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let type = d["type"] as? String else { continue }
            let t = (d["t"] as? NSNumber)?.doubleValue ?? 0
            func n(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
            switch type {
            case "start":
                if let r = d["rect"] as? [String: Any] {
                    func m(_ k: String) -> Double { (r[k] as? NSNumber)?.doubleValue ?? 0 }
                    frames.append((0, CGRect(x: m("x"), y: m("y"), width: m("width"), height: m("height"))))
                }
                e.scale = (d["scale"] as? NSNumber)?.doubleValue ?? 2
                e.virtual = (d["cursor"] as? String) == "virtual"
            case "window": frames.append((t, CGRect(x: n("x"), y: n("y"), width: n("width"), height: n("height"))))
            case "move", "drag", "down", "up": raw.append((t, type, n("x"), n("y"), d["button"] as? String ?? "left"))
            case "scroll": e.scrolls.append(t); e.scrollDeltas.append((t, n("dy")))
            case "key": e.keys.append(Key(t: t, chars: d["chars"] as? String ?? "", mods: d["mods"] as? [String] ?? []))
            case "cursor": e.cursors.append((t, d["id"] as? String ?? "arrow"))
            case "cursor-shape":
                let id = d["id"] as? String ?? ""
                e.shapes[id] = Shape(id: id, hotX: n("hotX"), hotY: n("hotY"), width: n("width"), height: n("height"))
            case "marker": e.markers.append((t, d["label"] as? String ?? ""))
            case "target": targetRows.append((t, CGRect(x: n("x"), y: n("y"), width: n("width"), height: n("height"))))
            default: break
            }
        }
        frames.sort { $0.0 < $1.0 }
        raw.sort { $0.t < $1.t }
        e.cursors.sort { $0.0 < $1.0 }
        let firstFrame = frames.first?.1 ?? CGRect(origin: .zero, size: CGSize(width: sourceSize.width / e.scale, height: sourceSize.height / e.scale))
        // the window's first logged frame is the content the recording shows; later frames move or resize it
        func frame(at t: Double) -> CGRect {
            var r = firstFrame
            for (ft, fr) in frames where ft <= t { r = fr }
            return r
        }
        func toSource(_ t: Double, _ x: Double, _ y: Double) -> (Double, Double) {
            let r = frame(at: t)
            guard r.width > 0, r.height > 0 else { return (x, y) }
            return ((x - r.minX) / r.width * sourceSize.width, (y - r.minY) / r.height * sourceSize.height)
        }
        for (t, r) in targetRows.sorted(by: { $0.0 < $1.0 }) {
            let (x0, y0) = toSource(t, r.minX, r.minY), (x1, y1) = toSource(t, r.maxX, r.maxY)
            e.targets.append((t, CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)))
        }
        var openDowns: [String: Int] = [:]
        for ev in raw {
            let (x, y) = toSource(ev.t, ev.x, ev.y)
            e.moves.append(Sample(t: ev.t, x: x, y: y))
            if ev.type == "down" {
                e.clicks.append(Click(t: ev.t, x: x, y: y, button: ev.button, up: nil))
                openDowns[ev.button] = e.clicks.count - 1
            } else if ev.type == "up", let i = openDowns[ev.button] {
                let c = e.clicks[i]
                e.clicks[i] = Click(t: c.t, x: c.x, y: c.y, button: c.button, up: ev.t)
                openDowns[ev.button] = nil
            }
        }
        return e
    }

    /// The cursor at t, straight-line between samples; before the first sample it sits at the first.
    public func position(at t: Double) -> CGPoint? {
        guard let first = moves.first else { return nil }
        if t <= first.t { return CGPoint(x: first.x, y: first.y) }
        let i = index(atOrBefore: t)
        let a = moves[i]
        guard i + 1 < moves.count else { return CGPoint(x: a.x, y: a.y) }
        let b = moves[i + 1]
        let k = (t - a.t) / max(1e-6, b.t - a.t)
        return CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }

    /// Index of the last move at or before t (0 when t is before every move).
    public func index(atOrBefore t: Double) -> Int {
        var lo = 0, hi = moves.count - 1
        guard hi >= 0, moves[0].t <= t else { return 0 }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if moves[mid].t <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// When the cursor last moved before t.
    public func lastMove(before t: Double) -> Double? {
        guard let first = moves.first, first.t <= t else { return nil }
        let i = index(atOrBefore: t)
        // walk back over samples that didn't move (button events repeat the position)
        var j = i
        while j > 0, moves[j].x == moves[j - 1].x, moves[j].y == moves[j - 1].y { j -= 1 }
        return moves[j].t
    }

    public func cursorID(at t: Double) -> String {
        var id = "arrow"
        for (ct, c) in cursors { if ct <= t { id = c } else { break } }
        return id
    }
}

extension EventTrack {
    /// How far the content scrolled (points, positive = moved down on screen) between two times.
    public func scrolled(from a: Double, to b: Double) -> Double {
        scrollDeltas.reduce(0) { $1.t > a && $1.t <= b ? $0 + $1.dy : $0 }
    }
}

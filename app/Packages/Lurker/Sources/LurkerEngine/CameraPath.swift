import CoreGraphics
import Foundation
import LurkerCore

/// The virtual camera over the canvas, as a pure function of program time. Built once from the zoom regions:
/// every change of target is one move from wherever the camera is to the new view, on a smootherstep ease, with the
/// zoom scaled about the point that stays fixed between the two views (so it pushes straight into the target).
public struct CameraPath: Sendable {
    public struct Move: Sendable {
        let start: Double
        let duration: Double
        let from: CGRect
        let to: CGRect
    }

    public let canvas: CGRect
    public let moves: [Move]

    /// A zoom in program time: hold `view` from start to end.
    public struct Shot: Sendable, Equatable {
        public var start: Double
        public var end: Double
        public var view: CGRect
        public var instant: Bool
        public init(start: Double, end: Double, view: CGRect, instant: Bool = false) {
            self.start = start; self.end = end; self.view = view; self.instant = instant
        }
    }

    /// `shots` sorted or not; overlapping shots: the later start wins.
    public init(canvas: CGSize, shots: [Shot], moveDuration: Double) {
        self.canvas = CGRect(origin: .zero, size: canvas)
        let full = self.canvas
        var targets: [(t: Double, view: CGRect, instant: Bool)] = []
        let sorted = shots.sorted { $0.start < $1.start }
        for (i, s) in sorted.enumerated() {
            let next = i + 1 < sorted.count ? sorted[i + 1].start : .infinity
            targets.append((s.start, s.view, s.instant))
            // zoom out so the camera is wide again by the shot's end, unless the next shot is close: then go straight there
            let outAt = max(s.start + (s.instant ? 0 : moveDuration), s.end - (s.instant ? 0 : moveDuration))
            if next - s.end > moveDuration * 0.5 { targets.append((min(outAt, next), full, s.instant)) }
        }
        var moves: [Move] = []
        var current = full
        for tg in targets {
            if let last = moves.last {
                current = Self.view(of: last, at: tg.t)
            }
            if Self.same(current, tg.view) { continue }
            moves.append(Move(start: tg.t, duration: tg.instant ? 0 : moveDuration, from: current, to: tg.view))
        }
        self.moves = moves
    }

    public func view(at t: Double) -> CGRect {
        var lo = 0, hi = moves.count - 1
        guard hi >= 0, moves[0].start <= t else { return canvas }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if moves[mid].start <= t { lo = mid } else { hi = mid - 1 }
        }
        return Self.view(of: moves[lo], at: t)
    }

    static func view(of m: Move, at t: Double) -> CGRect {
        guard m.duration > 0 else { return t >= m.start ? m.to : m.from }
        return lerp(m.from, m.to, ease((t - m.start) / m.duration))
    }

    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    /// Smootherstep: zero speed and acceleration at both ends.
    static func ease(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * c * (c * (c * 6 - 15) + 10)
    }

    /// Width on a log curve (zooming feels even); origin about the fixed point of the two rects.
    static func lerp(_ a: CGRect, _ b: CGRect, _ p: Double) -> CGRect {
        if abs(a.width - b.width) < 0.5 {
            return CGRect(x: a.minX + (b.minX - a.minX) * p, y: a.minY + (b.minY - a.minY) * p, width: a.width + (b.width - a.width) * p,
                          height: a.height + (b.height - a.height) * p)
        }
        let w = a.width * pow(b.width / a.width, p), h = a.height * pow(b.height / a.height, p)
        let fx = (a.minX * b.width - b.minX * a.width) / (b.width - a.width)
        let fy = (a.minY * b.height - b.minY * a.height) / (b.height - a.height)
        return CGRect(x: fx + (a.minX - fx) * w / a.width, y: fy + (a.minY - fy) * h / a.height, width: w, height: h)
    }

    /// The view for a zoom of `depth` centred on `focus` (canvas pixels), kept inside the canvas when zoomed in.
    public static func view(canvas: CGSize, depth: Double, focus: CGPoint) -> CGRect {
        let w = canvas.width / depth, h = canvas.height / depth
        var x = focus.x - w / 2, y = focus.y - h / 2
        if depth >= 1 {
            x = min(max(0, x), canvas.width - w)
            y = min(max(0, y), canvas.height - h)
        } else {
            x = (canvas.width - w) / 2; y = (canvas.height - h) / 2
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

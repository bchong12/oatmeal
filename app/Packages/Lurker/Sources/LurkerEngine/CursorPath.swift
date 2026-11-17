import CoreGraphics
import Foundation
import LurkerCore

/// The cursor as drawn: a smoothed path in source pixels, computed once (deterministic) from the event log.
///
/// The smoothing is a critically damped spring chasing the recorded path. A spring that chases a moving point trails it
/// by 2ζ/ω seconds, which is why smoothed cursors usually arrive after the button they're heading to has already lit
/// up. Here the spring chases the path that far *ahead*, so it arrives on time. It stiffens and lands exactly on the
/// click point around each click, stays tight while dragging, ignores tiny jitters, and jumps (no glide) when the
/// cursor reappears somewhere new after being still.
/// Repeatable randomness (SplitMix64), so a regenerated path is the same every render.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public struct CursorPath: Sendable {
    public enum Kind: String, Sendable { case arrow, hand, ibeam }

    /// Positions every 1/rate seconds from `start`.
    let rate = 240.0
    let start: Double
    let xs: [Float]
    let ys: [Float]
    public let clicks: [EventTrack.Click]
    let events: EventTrack
    let hideIdle: Double?
    let loop: Bool
    let duration: Double

    public struct Spring: Sendable {
        /// Natural frequency (Hz) and damping ratio.
        public var hz: Double
        public var zeta: Double
        /// Seconds a spring of this kind trails a steadily moving target.
        public var lag: Double { 2 * zeta / (2 * .pi * hz) }

        public static func preset(_ s: CursorStyle.Smoothing) -> Spring? {
            switch s {
            case .smooth: Spring(hz: 2.2, zeta: 1)
            case .medium: Spring(hz: 3.4, zeta: 1)
            case .rapid: Spring(hz: 5.5, zeta: 0.95)
            case .none: nil
            }
        }
    }

    public init(events: EventTrack, duration: Double, smoothing: CursorStyle.Smoothing, removeShakes: Bool, hideIdle: Double?, loop: Bool, planned: Bool = false) {
        self.events = events
        self.clicks = events.clicks
        self.hideIdle = hideIdle
        self.loop = loop
        self.duration = duration
        let planned = planned && !events.virtual && events.moves.count > 1
        let moves = planned ? Self.plan(events, duration: duration) : (removeShakes ? Self.steady(events.moves, scale: events.scale) : events.moves)
        start = moves.first?.t ?? 0
        guard !moves.isEmpty else { xs = []; ys = []; return }
        let end = max(duration, moves.last!.t)
        let n = Int(((end - start) * rate).rounded(.up)) + 1
        var xs = [Float](repeating: 0, count: n), ys = [Float](repeating: 0, count: n)

        func raw(_ t: Double) -> CGPoint {
            // linear between kept samples
            if t <= moves[0].t { return CGPoint(x: moves[0].x, y: moves[0].y) }
            var lo = 0, hi = moves.count - 1
            if t >= moves[hi].t { return CGPoint(x: moves[hi].x, y: moves[hi].y) }
            while hi - lo > 1 { let m = (lo + hi) / 2; if moves[m].t <= t { lo = m } else { hi = m } }
            let a = moves[lo], b = moves[hi], k = (t - a.t) / max(1e-6, b.t - a.t)
            return CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
        }

        // an agent's virtual cursor and a regenerated path are already planned like a hand: follow them exactly
        guard !events.virtual, !planned, let base = Spring.preset(smoothing) else {
            for i in 0..<n { let p = raw(start + Double(i) / rate); xs[i] = Float(p.x); ys[i] = Float(p.y) }
            self.xs = xs; self.ys = ys
            return
        }
        let clickWindows = clicks.map { (from: $0.t - 0.16, to: ($0.up ?? $0.t) + 0.04, at: CGPoint(x: $0.x, y: $0.y), held: ($0.up ?? $0.t) - $0.t > 0.25) }
        var px = moves[0].x, py = moves[0].y, vx = 0.0, vy = 0.0
        var nextMove = 0
        var lastRawMove = moves[0].t
        let dt = 0.001
        var t = start
        var out = 0
        while out < n {
            // teleport when the cursor reappears far away after a pause (another display, a hidden cursor)
            while nextMove < moves.count && moves[nextMove].t <= t {
                let m = moves[nextMove]
                if m.t - lastRawMove > 1.5, hypot(m.x - px, m.y - py) > 300 * events.scale / 2 { px = m.x; py = m.y; vx = 0; vy = 0 }
                lastRawMove = m.t
                nextMove += 1
            }
            var spring = base
            var target: CGPoint
            if let c = clickWindows.first(where: { t >= $0.from && t <= $0.to }) {
                // land exactly on the click, then hold; long presses are drags: follow tightly instead
                if c.held && t > c.from + 0.16 { target = raw(t); spring.hz = base.hz * 3 }
                else { target = c.at; spring.hz = base.hz * 2.6 }
            } else {
                target = raw(min(t + base.lag, moves.last!.t))
            }
            let w = 2 * .pi * spring.hz
            // semi-implicit Euler on x'' = w²(target − x) − 2ζw x'
            vx += (w * w * (target.x - px) - 2 * spring.zeta * w * vx) * dt
            vy += (w * w * (target.y - py) - 2 * spring.zeta * w * vy) * dt
            px += vx * dt; py += vy * dt
            t += dt
            while out < n && start + Double(out) / rate <= t {
                xs[out] = Float(px); ys[out] = Float(py); out += 1
            }
        }
        self.xs = xs; self.ys = ys
    }

    // MARK: regenerated path

    struct Anchor { var t: Double; var p: CGPoint; var click: Bool; var dragUntil: Double? }

    /// A new cursor path through the moments that matter, with the wandering in between dropped.
    /// Anchors: where the take starts, every click (landed exactly, with the real path kept through drags), where
    /// typing and scrolling happen, and every deliberate pause (still for 0.6 s or more). Between anchors the cursor
    /// rests, then makes one decisive straight move (the same Fitts's-law glide the agent cursor uses) that arrives just
    /// before the next click. Seeded from the take, so the same take always gives the same path.
    static func plan(_ e: EventTrack, duration: Double) -> [EventTrack.Sample] {
        let moves = e.moves
        guard let first = moves.first else { return [] }
        let still = 4 * e.scale
        func at(_ t: Double) -> CGPoint { e.position(at: t) ?? CGPoint(x: first.x, y: first.y) }
        var anchors = [Anchor(t: first.t, p: CGPoint(x: first.x, y: first.y), click: false, dragUntil: nil)]
        // clicks; a press held while the cursor travels is a drag
        for c in e.clicks {
            let up = c.up ?? c.t
            var travelled = 0.0
            let i0 = e.index(atOrBefore: c.t)
            var i = i0
            while i < moves.count && moves[i].t <= up { travelled = max(travelled, hypot(moves[i].x - c.x, moves[i].y - c.y)); i += 1 }
            anchors.append(Anchor(t: c.t, p: CGPoint(x: c.x, y: c.y), click: true, dragUntil: travelled > still * 1.5 ? up : nil))
        }
        // deliberate pauses
        var i = 0
        while i < moves.count {
            var j = i
            while j + 1 < moves.count && hypot(moves[j + 1].x - moves[i].x, moves[j + 1].y - moves[i].y) < still { j += 1 }
            let end = j + 1 < moves.count ? moves[j + 1].t : duration
            if end - moves[i].t >= 0.6 { anchors.append(Anchor(t: moves[i].t, p: CGPoint(x: moves[i].x, y: moves[i].y), click: false, dragUntil: nil)) }
            i = j + 1
        }
        // where typing and scrolling start, the cursor is parked
        for k in Planner.typingBursts(e) { anchors.append(Anchor(t: k.start, p: at(k.start), click: false, dragUntil: nil)) }
        for (n, t) in e.scrolls.enumerated() where n == 0 || t - e.scrolls[n - 1] > 0.5 { anchors.append(Anchor(t: t, p: at(t), click: false, dragUntil: nil)) }
        anchors.sort { $0.t < $1.t }
        // one anchor per moment; a click wins over a pause at the same time
        var kept: [Anchor] = []
        for a in anchors {
            if let last = kept.last, a.t - last.t < 0.12 {
                if a.click && !last.click { kept[kept.count - 1] = a }
                continue
            }
            kept.append(a)
        }

        var rng = SeededRandom(seed: UInt64(bitPattern: Int64((first.x * 7 + first.y * 13 + Double(moves.count)).rounded())))
        var out: [EventTrack.Sample] = [EventTrack.Sample(t: kept[0].t, x: kept[0].p.x, y: kept[0].p.y)]
        var pos = kept[0].p, clock = kept[0].t
        for b in kept.dropFirst() where b.t > clock {
            let d = hypot(b.p.x - pos.x, b.p.y - pos.y)
            let arrive = b.t - (b.click ? 0.18 : 0)
            if d > still {
                // in points, so Fitts's law sees the distances a hand does
                let a = CGPoint(x: pos.x / e.scale, y: pos.y / e.scale), z = CGPoint(x: b.p.x / e.scale, y: b.p.y / e.scale)
                let natural = Glide.duration(distance: d / e.scale)
                let room = arrive - clock
                let T = min(natural, max(0.12, room))
                let depart = max(clock, arrive - T)
                let g = Glide.path(from: a, to: z, duration: T, using: &rng)
                out.append(EventTrack.Sample(t: depart, x: pos.x, y: pos.y))
                for s in g.samples { out.append(EventTrack.Sample(t: depart + s.t, x: s.x * e.scale, y: s.y * e.scale)) }
            }
            out.append(EventTrack.Sample(t: b.t, x: b.p.x, y: b.p.y))
            pos = b.p; clock = b.t
            if let until = b.dragUntil {
                // a drag follows the hand exactly
                var k = e.index(atOrBefore: b.t)
                while k < moves.count && moves[k].t <= until {
                    if moves[k].t > clock { out.append(moves[k]) }
                    k += 1
                }
                if let last = out.last { pos = CGPoint(x: last.x, y: last.y); clock = max(clock, last.t) }
            }
        }
        out.append(EventTrack.Sample(t: max(clock, duration), x: pos.x, y: pos.y))
        return out.sorted { $0.t < $1.t }
    }

    /// Drops jitter: moves of under a point and a half that come back within 100 ms.
    static func steady(_ moves: [EventTrack.Sample], scale: Double) -> [EventTrack.Sample] {
        guard moves.count > 2 else { return moves }
        let tiny = 1.5 * scale
        var out = [moves[0]]
        for m in moves.dropFirst() {
            let last = out[out.count - 1]
            if hypot(m.x - last.x, m.y - last.y) < tiny && m.t - last.t < 0.1 { continue }
            out.append(m)
        }
        if let l = moves.last, out.last != l { out.append(l) }
        return out
    }

    public var isEmpty: Bool { xs.isEmpty }

    /// Where the cursor's hotspot is at source time t.
    public func position(at t: Double) -> CGPoint? {
        guard !xs.isEmpty else { return nil }
        var p = sample(t)
        if loop, duration > 2, t > duration - 1 {
            // glide back to where the take began so the video loops
            let k = CameraPath.ease((t - (duration - 1)) / 1)
            let a = sample(start)
            p = CGPoint(x: p.x + (a.x - p.x) * k, y: p.y + (a.y - p.y) * k)
        }
        return p
    }

    private func sample(_ t: Double) -> CGPoint {
        let f = (t - start) * rate
        if f <= 0 { return CGPoint(x: Double(xs[0]), y: Double(ys[0])) }
        let i = Int(f)
        if i >= xs.count - 1 { return CGPoint(x: Double(xs[xs.count - 1]), y: Double(ys[ys.count - 1])) }
        let k = f - Double(i)
        return CGPoint(x: Double(xs[i]) + Double(xs[i + 1] - xs[i]) * k, y: Double(ys[i]) + Double(ys[i + 1] - ys[i]) * k)
    }

    /// 1 while moving; fades out after the idle time, back in at the next move.
    public func alpha(at t: Double) -> Double {
        guard let hideIdle, let last = events.lastMove(before: t) else { return 1 }
        let still = t - last
        return still <= hideIdle ? 1 : max(0, 1 - (still - hideIdle) / 0.2)
    }

    public func kind(at t: Double) -> Kind {
        let id = events.cursorID(at: t)
        if id.contains("pointingHand") || id.contains("hand") { return .hand }
        if id.contains("iBeam") || id.contains("ibeam") { return .ibeam }
        return .arrow
    }

    /// The most recent click within `window` seconds before t, and its age.
    public func click(at t: Double, window: Double = 0.5) -> (EventTrack.Click, Double)? {
        guard let c = clicks.last(where: { $0.t <= t && t - $0.t < window }) else { return nil }
        return (c, t - c.t)
    }
}

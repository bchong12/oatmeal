import CoreGraphics
import Foundation

/// One cursor move: Fitts's-law duration and a minimum-jerk speed profile with an early peak (fast start, long
/// settle), along a straight line to the target. Samples at 120 Hz, times from 0.
public enum Glide {
    public struct Sample: Sendable {
        public let t: Double; public let x: Double; public let y: Double
        public init(t: Double, x: Double, y: Double) { self.t = t; self.x = x; self.y = y }
    }

    public static func path(from a: CGPoint, to b: CGPoint, targetWidth: Double = 48, duration: Double? = nil, slow: Bool = false, pace: Double = 1) -> (samples: [Sample], duration: Double) {
        var g = SystemRandomNumberGenerator()
        return path(from: a, to: b, targetWidth: targetWidth, duration: duration, slow: slow, pace: pace, using: &g)
    }

    /// Fitts's-law duration of a move, before the small random variation.
    public static func duration(distance d: Double, targetWidth: Double = 48) -> Double {
        min(1.4, max(0.28, 0.20 + 0.14 * log2(d / max(14, targetWidth) + 1)))
    }

    /// The same, with the randomness drawn from `rng` (seed it to make the path repeatable).
    public static func path<G: RandomNumberGenerator>(from a: CGPoint, to b: CGPoint, targetWidth: Double = 48, duration: Double? = nil, slow: Bool = false,
                                                      pace: Double = 1, using rng: inout G) -> (samples: [Sample], duration: Double) {
        let dx = b.x - a.x, dy = b.y - a.y, d = hypot(dx, dy)
        guard d > 1.5 else { return ([], 0) }
        func rnd(_ x: Double, _ y: Double) -> Double { Double.random(in: x...y, using: &rng) }
        var T = duration ?? (0.20 + 0.14 * log2(d / max(14, targetWidth) + 1)) * rnd(0.92, 1.08) * pace
        if slow { T *= 1.35 }
        if duration == nil { T = min(1.4 * pace, max(0.28, T)) }
        func profile(_ u: Double) -> Double { let v = pow(u, 0.82); return v * v * v * (v * (v * 6 - 15) + 10) }
        var out: [Sample] = []
        let n = max(2, Int((T * 120).rounded()))
        for i in 1...n {
            let k = profile(Double(i) / Double(n))
            out.append(Sample(t: T * Double(i) / Double(n), x: a.x + dx * k, y: a.y + dy * k))
        }
        return (out, T)
    }
}

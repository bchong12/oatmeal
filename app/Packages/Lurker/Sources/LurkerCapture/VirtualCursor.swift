import CoreGraphics
import Foundation
import LurkerCore

/// The agent's cursor in a take. The agent says what it intends (click this, read that line, rest here, scroll);
/// this turns it into the motion a hand makes and writes ordinary move/down/up rows (marked virtual) to the event log:
///  - duration from Fitts's law (distance and target size), a little different each time
///  - a straight line with a fast start and a long settle
///  - it aims somewhere inside the target, not its exact centre, and hovers briefly before clicking
/// The real mouse is never touched. Each call returns how long until the moment of the action, so the agent's real
/// click (an Accessibility press, a CDP click) can land exactly when the drawn cursor clicks.
public final class VirtualCursor: @unchecked Sendable {
    public enum Action: String, Codable, Sendable { case move, click, doubleClick = "double_click", rightClick = "right_click", hover, read, rest, scroll }

    let log: @Sendable ([String: Any], Double) -> Void
    let now: @Sendable () -> Double
    private let lock = NSLock()
    private var position: CGPoint
    private var busyUntil = 0.0
    private var shape = "arrow"
    private var rng: SystemRandomNumberGenerator

    /// `log(row, t)` writes an event row at take time t; `now()` is the take's current time.
    init(start: CGPoint, log: @escaping @Sendable ([String: Any], Double) -> Void, now: @escaping @Sendable () -> Double) {
        position = start; self.log = log; self.now = now; rng = SystemRandomNumberGenerator()
    }

    public struct Plan: Sendable { public let wait: Double; public let at: CGPoint; public let ends: Double }

    /// Plans and logs one gesture toward `target` (global points). `size` is the target's size in points.
    public func perform(_ action: Action, to target: CGPoint, size: CGSize? = nil, readTo: CGPoint? = nil, scrollBy: Double? = nil, duration: Double? = nil) -> Plan {
        lock.withLock {
            let t0 = max(now(), busyUntil)
            var clock = t0
            func rnd(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b, using: &rng) }
            var aim = target
            if let s = size, action != .rest && action != .scroll {
                aim.x += rnd(-0.16, 0.16) * min(s.width, 300)
                aim.y += rnd(-0.14, 0.14) * min(s.height, 80)
            }
            if action == .scroll {
                let T = duration ?? 2.5, dy = scrollBy ?? 400
                let n = max(2, Int(T * 30))
                for i in 0..<n { log(["type": "scroll", "dy": -dy / Double(n), "x": position.x, "y": position.y, "virtual": true], clock + T * Double(i) / Double(n)) }
                busyUntil = clock + T
                return Plan(wait: busyUntil - now(), at: position, ends: busyUntil)
            }
            clock = glide(from: position, to: aim, at: clock, targetWidth: size?.width, duration: duration, slow: action == .rest)
            position = aim
            var actionAt = clock
            switch action {
            case .click, .doubleClick, .rightClick:
                clock += rnd(0.12, 0.22)
                actionAt = clock
                let button = action == .rightClick ? "right" : "left"
                for n in 1...(action == .doubleClick ? 2 : 1) {
                    log(["type": "down", "x": aim.x, "y": aim.y, "button": button, "clicks": n, "virtual": true], clock)
                    clock += rnd(0.07, 0.10)
                    log(["type": "up", "x": aim.x, "y": aim.y, "button": button, "virtual": true], clock)
                    clock += 0.06
                }
            case .read:
                if let end = readTo {
                    let d = hypot(end.x - aim.x, end.y - aim.y)
                    let T = duration ?? max(0.8, d / rnd(220, 300))
                    let n = max(2, Int(T * 60))
                    for i in 1...n {
                        let u = Double(i) / Double(n), s = u * u * (3 - 2 * u)
                        let wob = sin(u * .pi * 2) * 2.5
                        log(["type": "move", "x": aim.x + (end.x - aim.x) * s, "y": aim.y + (end.y - aim.y) * s + wob, "virtual": true], clock + T * u)
                    }
                    clock += T
                    position = end
                }
                actionAt = clock
            default:
                actionAt = clock
            }
            busyUntil = clock
            return Plan(wait: max(0, actionAt - now()), at: aim, ends: clock)
        }
    }

    /// Cursor shape from now on: arrow, pointingHand, iBeam…
    public func setShape(_ id: String) {
        lock.withLock {
            guard id != shape else { return }
            shape = id
            log(["type": "cursor", "id": id], max(now(), busyUntil))
        }
    }

    /// Records the element an action targets (global points), so automatic zooms frame exactly that element.
    public func target(_ rect: CGRect, label: String? = nil) {
        var row: [String: Any] = ["type": "target", "x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
        if let label { row["label"] = label }
        log(row, lock.withLock { max(now(), busyUntil) })
    }

    /// One human-looking move; returns when it ends.
    private func glide(from a: CGPoint, to b: CGPoint, at t0: Double, targetWidth: CGFloat?, duration: Double?, slow: Bool) -> Double {
        let g = Glide.path(from: a, to: b, targetWidth: Double(targetWidth ?? 48), duration: duration, slow: slow)
        for p in g.samples { log(["type": "move", "x": (p.x * 10).rounded() / 10, "y": (p.y * 10).rounded() / 10, "virtual": true], t0 + p.t) }
        return t0 + g.duration
    }
}

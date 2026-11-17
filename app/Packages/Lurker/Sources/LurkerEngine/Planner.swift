import AVFoundation
import CoreGraphics
import Foundation
import LurkerCore

/// Plans automatic edits from what happened in a take: zoom shots around clicks, typing and agent targets; speed-ups
/// for long typing and idle stretches. Everything it makes is marked auto, so re-planning never touches manual work.
///
/// Zoom shot rules (Lurker's own):
///  - each click is a shot from 0.5 s before to 1.5 s after; typing is a shot from its first key to just after its last
///  - the take opens and closes wide: nothing starts in the first second or runs into the last 0.8 s (the stop click)
///  - shots within 3 s of each other merge when everything they show fits one view; otherwise, when the wide gap
///    between them would be under 1.5 s, the camera pans straight from one to the next instead of bouncing out
///  - every shot holds at least 1.8 s
///  - depth is the deepest of 2.5, 2, 1.8, 1.5 and 1.25 that keeps the whole target plus a 12% margin in view
public enum Planner {
    public struct Options: Codable, Sendable {
        public var zooms = true
        public var typing = true
        public var idle = false
        public init() {}
    }

    public struct Plan: Sendable {
        public var zooms: [Zoom] = []
        public var speeds: [Speed] = []
        public var notes: [String] = []
    }

    struct Candidate { var start: Double; var end: Double; var box: CGRect; let kind: String }

    static let depths = [2.5, 2.0, 1.8, 1.5, 1.25]
    static let margin = 0.12

    public static func plan(take: String, events e: EventTrack, duration: Double, crop: CGRect, frames: [FrameActivity.Sample]? = nil, options: Options = Options()) -> Plan {
        var plan = Plan()
        let pt = e.scale
        var cands: [Candidate] = []
        // agent takes say exactly which element they acted on
        for target in e.targets where target.t > 0.8 && target.t < duration - 1 {
            cands.append(Candidate(start: target.t - 0.5, end: target.t + 1.5, box: target.rect, kind: "target"))
        }
        for c in e.clicks where c.t > 0.8 && c.t < duration - 1 {
            if e.targets.contains(where: { abs($0.t - c.t) < 0.3 }) { continue }
            // the thing clicked is rarely bigger than a toolbar button
            let box = CGRect(x: c.x - 70 * pt, y: c.y - 35 * pt, width: 140 * pt, height: 70 * pt)
            cands.append(Candidate(start: c.t - 0.5, end: max(c.t, c.up ?? c.t) + 1.5, box: box, kind: "click"))
        }
        let bursts = typingBursts(e)
        if options.typing {
            for b in bursts where b.end - b.start >= 0.8 && b.start > 0.8 {
                let at = e.position(at: b.start) ?? CGPoint(x: crop.midX, y: crop.midY)
                let box = e.targets.last(where: { $0.t <= b.start })?.rect ?? CGRect(x: at.x - 200 * pt, y: at.y - 30 * pt, width: 400 * pt, height: 60 * pt)
                cands.append(Candidate(start: b.start - 0.4, end: b.end + 0.8, box: box, kind: "typing"))
            }
        }
        if options.zooms {
            plan.zooms = shots(cands.sorted { $0.start < $1.start }, duration: duration, crop: crop).map { c in
                Zoom(take: take, start: c.start, end: c.end, origin: .auto, depth: depth(for: c.box, crop: crop))
            }
            plan.notes.append("\(plan.zooms.count) zooms from \(e.clicks.count) clicks, \(bursts.count) typing bursts, \(e.targets.count) targets")
        }
        if options.typing {
            for b in bursts where b.end - b.start >= 4 {
                plan.speeds.append(Speed(take: take, start: b.start + 0.5, end: b.end - 0.3, origin: .auto, rate: 2.5, audio: .duck))
            }
        }
        if options.idle {
            for (a, b) in idle(e, frames: frames, duration: duration) {
                plan.speeds.append(Speed(take: take, start: a, end: b, origin: .auto, rate: 4, audio: .duck))
            }
        }
        plan.speeds = plan.speeds.filter { $0.end - $0.start > 0.5 }.sorted { $0.start < $1.start }
        // speed-ups never overlap each other
        var kept: [Speed] = []
        for s in plan.speeds where !kept.contains(where: { $0.start < s.end && s.start < $0.end }) { kept.append(s) }
        plan.speeds = kept
        return plan
    }

    static func shots(_ cands: [Candidate], duration: Double, crop: CGRect) -> [Candidate] {
        var out: [Candidate] = []
        for var c in cands {
            c.start = max(1.0, c.start)
            c.end = min(duration - 0.8, c.end)
            guard c.end - c.start > 0.3 else { continue }
            if var last = out.last, c.start - last.end < 3 {
                let union = last.box.union(c.box)
                if depth(for: union, crop: crop) >= 1.25, fits(union, crop: crop) {
                    last.end = max(last.end, c.end); last.box = union
                    out[out.count - 1] = last
                    continue
                }
                // too far apart to share a view: pan straight across rather than bounce out and in
                if c.start - last.end < 1.5 { out[out.count - 1].end = c.start }
            }
            out.append(c)
        }
        // hold each shot long enough to read, without running into the next
        for i in out.indices {
            let next = i + 1 < out.count ? out[i + 1].start : duration - 0.8
            if out[i].end - out[i].start < 1.8 { out[i].end = min(next, out[i].start + 1.8) }
        }
        return out.filter { $0.end - $0.start >= 0.6 }
    }

    static func fits(_ box: CGRect, crop: CGRect) -> Bool {
        box.width * (1 + 2 * margin) <= crop.width && box.height * (1 + 2 * margin) <= crop.height
    }

    /// The deepest zoom that keeps the box and its margin in view (1 when nothing deeper fits).
    static func depth(for box: CGRect, crop: CGRect) -> Double {
        for d in depths where box.width * (1 + 2 * margin) <= crop.width / d && box.height * (1 + 2 * margin) <= crop.height / d { return d }
        return 1
    }

    /// Runs of keystrokes with no gap over 1.5 s.
    static func typingBursts(_ e: EventTrack) -> [(start: Double, end: Double, keys: Int)] {
        var out: [(Double, Double, Int)] = []
        for k in e.keys where !k.mods.contains("command") && !k.mods.contains("control") {
            if let last = out.last, k.t - last.1 <= 1.5 { out[out.count - 1].1 = k.t; out[out.count - 1].2 += 1 }
            else { out.append((k.t, k.t, 1)) }
        }
        return out.filter { $0.2 >= 4 }.map { (start: $0.0, end: $0.1, keys: $0.2) }
    }

    /// Stretches of at least 3 s with no input and no real change on screen (a blinking caret doesn't count).
    static func idle(_ e: EventTrack, frames: [FrameActivity.Sample]?, duration: Double) -> [(Double, Double)] {
        var marks = e.moves.map(\.t) + e.clicks.map(\.t) + e.scrolls + e.keys.map(\.t)
        if let frames {
            let sizes = frames.filter { !$0.key }.map(\.bytes).sorted()
            let median = sizes.isEmpty ? 0 : sizes[sizes.count / 2]
            marks += frames.filter { !$0.key && $0.bytes > max(6_000, median * 3) }.map(\.t)
        }
        marks.sort()
        var out: [(Double, Double)] = []
        var from = 0.0
        for t in marks + [duration] {
            if t - from >= 3 { out.append((from + 0.6, t - 0.6)) }
            from = max(from, t)
        }
        return out
    }
}

/// How much each frame of a screen recording changed, read from the compressed samples (no decoding). Screen files only
/// hold frames when something changed, and a frame's size tracks how much did.
public enum FrameActivity {
    public struct Sample: Sendable { public let t: Double; public let bytes: Int; public let key: Bool }

    public static func read(_ url: URL) async throws -> [Sample] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(out)
        guard reader.startReading() else { return [] }
        var samples: [Sample] = []
        while let sb = out.copyNextSampleBuffer() {
            guard sb.numSamples > 0 else { continue }
            let attachments = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]])?.first
            let notSync = attachments?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
            samples.append(Sample(t: sb.presentationTimeStamp.seconds, bytes: sb.totalSampleSize, key: !notSync))
        }
        return samples
    }
}

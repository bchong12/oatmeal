import Foundation

/// Source time ↔ program time. Clips in order, minus cuts, stretched by speed regions, as straight-line segments.
public struct TimeMap: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        public let clip: String
        public let take: String
        public let sourceStart: Double
        public let sourceEnd: Double
        /// Source seconds per program second.
        public let rate: Double
        public let programStart: Double
        public let programEnd: Double

        func source(at program: Double) -> Double { sourceStart + (program - programStart) * rate }
    }

    /// A stretch of one take. `clip` is set when it came from program time.
    public struct SourceRange: Equatable, Sendable {
        public let take: String
        public let start: Double
        public let end: Double
        public let clip: String?
        public init(take: String, start: Double, end: Double, clip: String? = nil) {
            self.take = take; self.start = start; self.end = end; self.clip = clip
        }
    }

    /// Pieces shorter than this vanish (float noise between touching cuts).
    static let epsilon = 1e-6

    public let segments: [Segment]
    public var duration: Double { segments.last?.programEnd ?? 0 }

    public init(_ project: Project) {
        var out: [Segment] = []
        var cursor = 0.0
        for clip in project.clips {
            let cuts = Self.merged(project.regions.cut.filter { $0.take == clip.take }.map { ($0.start, $0.end) })
            let speeds = project.regions.speed.filter { $0.take == clip.take }.sorted { $0.start < $1.start }
            for (a, b) in Self.subtract(cuts, from: (clip.start, clip.end)) {
                // split where speed regions start and end, then give each piece its rate
                var marks = [a, b]
                for s in speeds { marks += [s.start, s.end].filter { $0 > a && $0 < b } }
                marks.sort()
                for (p, q) in zip(marks, marks.dropFirst()) where q - p >= Self.epsilon {
                    let mid = (p + q) / 2
                    let rate = speeds.first { mid >= $0.start && mid < $0.end }?.rate ?? 1
                    let length = (q - p) / rate
                    out.append(Segment(clip: clip.id, take: clip.take, sourceStart: p, sourceEnd: q, rate: rate,
                                       programStart: cursor, programEnd: cursor + length))
                    cursor += length
                }
            }
        }
        segments = out
    }

    /// What plays at a program time: the segment's take and source time. At a boundary the later segment wins.
    public func locate(_ program: Double) -> (clip: String, take: String, source: Double)? {
        guard !segments.isEmpty else { return nil }
        let t = min(max(program, 0), duration)
        var lo = 0, hi = segments.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if segments[mid].programStart <= t { lo = mid } else { hi = mid - 1 }
        }
        let s = segments[lo]
        return (s.clip, s.take, min(s.source(at: t), s.sourceEnd))
    }

    /// Every program time that shows this source instant: none when it's cut, several when clips repeat it.
    public func program(take: String, source: Double) -> [Double] {
        segments.filter { $0.take == take && source >= $0.sourceStart && source < $0.sourceEnd }
            .map { $0.programStart + (source - $0.sourceStart) / $0.rate }
    }

    /// The source stretches a program range covers, in program order. Cut material between them isn't included.
    public func sourceRanges(from start: Double, to end: Double) -> [SourceRange] {
        guard end > start else { return [] }
        return segments.compactMap { s in
            let a = max(start, s.programStart), b = min(end, s.programEnd)
            guard b - a >= Self.epsilon else { return nil }
            return SourceRange(take: s.take, start: s.source(at: a), end: min(s.source(at: b), s.sourceEnd), clip: s.clip)
        }
    }

    // MARK: interval helpers

    /// Union of intervals; touching ones join.
    static func merged(_ intervals: [(Double, Double)]) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        for (a, b) in intervals.sorted(by: { $0.0 < $1.0 }) {
            if let last = out.last, a <= last.1 + epsilon { out[out.count - 1].1 = max(last.1, b) }
            else { out.append((a, b)) }
        }
        return out
    }

    /// `range` minus sorted, merged `holes`.
    static func subtract(_ holes: [(Double, Double)], from range: (Double, Double)) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        var from = range.0
        for (a, b) in holes where b > range.0 && a < range.1 {
            if a - from >= epsilon { out.append((from, a)) }
            from = max(from, b)
        }
        if range.1 - from >= epsilon { out.append((from, range.1)) }
        return out
    }
}

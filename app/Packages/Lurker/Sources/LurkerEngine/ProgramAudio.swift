import Accelerate
import AVFoundation
import CryptoKit
import Foundation
import LurkerCore

/// The program's system audio, rendered offline into one file that the composition plays from start to end.
///
/// AVFoundation's own editing depends on thread timing wherever the sound changes course. Its time pitch (a
/// `scaleTimeRange`d stretch read with `.spectral`) sometimes drops 64 ms to silence, or stretches differently, soon
/// after a splice, and the drop sounds as a burst; a switch to another file, and volume ramps close together, also come
/// out differently from one read to the next. So the cuts, the stretches (AVAudioUnitTimePitch in an offline engine) and
/// the volume are all done here, on one thread, and every read of the program (the editor's preview, every export)
/// hears the same samples.
enum ProgramAudio {
    static let rate = 48_000.0
    /// Each side of the dip at a splice (12 ms), so cuts never click. A change of volume ramps over the same.
    static let dip = 576
    /// Where a stretch meets 1× audio of the same moment it fades into the take's own samples over this long (10 ms), so
    /// the join is seamless.
    static let fade = 480
    /// Output samples the time pitch runs before a stretch that carries on from 1× audio, so its first windows are full.
    static let preroll = 4096
    /// Bumped when the rendering changes, so older files aren't reused.
    static let version = 1
    static let chunk = 4096

    struct Source {
        let asset: AVURLAsset
        let track: AVAssetTrack
        /// Changes when the recording does, for the cache.
        let stamp: String
    }

    /// One segment's sound: program samples `from..<to` play source samples `start..<start + frames` of `take`.
    struct Part {
        let take: String
        let from: Int, to: Int
        let start: Int, frames: Int
        let speed: Double
        let gain: Float
        /// Whether it carries on from the part before (after) with no splice between them.
        let joinsBefore: Bool, joinsAfter: Bool

        var length: Int { to - from }
        var key: String { "\(take) \(from) \(to) \(start) \(frames) \(speed.bitPattern) \(gain.bitPattern) \(joinsBefore) \(joinsAfter)" }
    }

    static func parts(_ project: Project, map: TimeMap) -> [Part] {
        func samples(_ s: Double) -> Int { Int((s * rate).rounded()) }
        func joins(_ a: TimeMap.Segment, _ b: TimeMap.Segment) -> Bool { a.take == b.take && abs(b.sourceStart - a.sourceEnd) <= 0.005 }
        let base = Float(project.audio.systemVolume ?? 1)
        let segments = map.segments
        return segments.enumerated().map { i, seg in
            var gain = base
            if abs(seg.rate - 1) > 1e-6 {
                let policy = project.regions.speed.first { $0.take == seg.take && seg.sourceStart >= $0.start - 1e-6 && seg.sourceEnd <= $0.end + 1e-6 }?.audio
                    ?? (seg.rate > 2 ? .duck : .keep)
                gain = switch policy { case .keep: base; case .duck: base * 0.2; case .mute: 0 }
            }
            let start = samples(seg.sourceStart)
            return Part(take: seg.take, from: samples(seg.programStart), to: samples(seg.programEnd), start: start, frames: samples(seg.sourceEnd) - start,
                        speed: abs(seg.rate - 1) > 1e-6 ? seg.rate : 1, gain: gain,
                        joinsBefore: i > 0 && joins(segments[i - 1], seg), joinsAfter: i + 1 < segments.count && joins(seg, segments[i + 1]))
        }
    }

    /// The program's system audio as a file of `frames` samples, from the cache in `dir` when this program was rendered
    /// before; nil when no segment's take has any.
    static func file(_ project: Project, map: TimeMap, sources: [String: Source], dir: URL) async throws -> (url: URL, frames: Int)? {
        let parts = parts(project, map: map)
        guard parts.contains(where: { sources[$0.take] != nil }), let frames = parts.last?.to, frames > 0 else { return nil }
        let key = (["v\(version)"] + parts.map { p in "\(p.key) \(sources[p.take].map { "\($0.asset.url.path) \($0.stamp)" } ?? "-")" }).joined(separator: "\n")
        let url = dir.appending(path: "p-\(hash(key)).caf")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return (url, frames)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // programs are big and remade at every edit; pieces are small and outlast edits elsewhere
        prune(dir, prefix: "p-", keep: 4, after: 120)
        prune(dir, prefix: "s-", keep: 0, after: 86_400)

        let splices = parts.dropFirst().filter { !$0.joinsBefore }.map(\.from)
        try write(to: url, frames: frames) { out in
            for (i, part) in parts.enumerated() {
                // a change of volume where the sound carries on ramps in
                let was = part.joinsBefore ? parts[i - 1].gain : part.gain
                var k = part.from
                try chunks(of: part, source: sources[part.take], dir: dir) { chunk in
                    let n = chunk[0].count
                    var gains = [Float](repeating: part.gain, count: n)
                    for j in max(k, part.from)..<max(k, min(k + n, part.from + dip)) where was != part.gain {
                        gains[j - k] = was + (part.gain - was) * Float(j - part.from) / Float(dip)
                    }
                    // the dips: the sound falls to nothing at each splice and comes back over `dip` samples either side
                    for b in splices where b + dip > k && b - dip < k + n {
                        for j in max(k, b - dip)..<min(k + n, b + dip) { gains[j - k] *= Float(abs(j - b)) / Float(dip) }
                    }
                    var scaled = chunk
                    for c in 0..<2 { vDSP.multiply(chunk[c], gains, result: &scaled[c]) }
                    try out(scaled)
                    k += n
                }
            }
        }
        return (url, frames)
    }

    /// A part's sound in chunks: the take's samples at 1×, its stretch, or silence when the take has no audio.
    static func chunks(of part: Part, source: Source?, dir: URL, _ body: ([[Float]]) throws -> Void) throws {
        let all: [[Float]]?
        let decoder: Decoder?
        if let source, part.speed != 1 { all = try stretch(part, source: source, dir: dir); decoder = nil }
        else { all = nil; decoder = try source.map { try Decoder($0, from: part.start) } }
        var done = 0
        while done < part.length {
            let n = min(chunk, part.length - done)
            if let all { try body([Array(all[0][done..<done + n]), Array(all[1][done..<done + n])]) }
            else if let decoder { try body(decoder.read(n)) }
            else { try body([[Float]](repeating: [Float](repeating: 0, count: n), count: 2)) }
            done += n
        }
    }

    /// The part through the time pitch, from the cache when it was rendered before. Output sample k is the source at
    /// `start + k × speed` (the time pitch has no latency); where the part carries on from (into) 1× audio it fades from
    /// (into) the take's own samples, and at a splice it hears silence beyond the part, so cut audio never leaks in.
    static func stretch(_ part: Part, source: Source, dir: URL) throws -> [[Float]] {
        let url = dir.appending(path: "s-\(hash("v\(version) \(source.asset.url.path) \(source.stamp) \(part.start) \(part.frames) \(part.length) \(part.speed.bitPattern) \(part.joinsBefore) \(part.joinsAfter)")).caf")
        if let cached = try? read(url) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return cached
        }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: AVAudioFrameCount(chunk))
        let before = part.joinsBefore ? Int((Double(preroll) * part.speed).rounded()) : 0
        let input = try Decoder(source, from: part.start - before, limit: part.joinsAfter ? nil : part.start + part.frames)
        let feed = AVAudioSourceNode(format: fmt) { _, _, count, list in
            let samples = input.read(Int(count))
            for (c, b) in UnsafeMutableAudioBufferListPointer(list).enumerated() {
                samples[c].withUnsafeBytes { b.mData!.copyMemory(from: $0.baseAddress!, byteCount: Int(count) * 4) }
            }
            return noErr
        }
        let pitch = AVAudioUnitTimePitch()
        pitch.rate = Float(part.speed)
        pitch.overlap = 16
        engine.attach(feed)
        engine.attach(pitch)
        engine.connect(feed, to: pitch, format: fmt)
        engine.connect(pitch, to: engine.mainMixerNode, format: fmt)
        try engine.start()
        defer { engine.stop() }
        // the preroll's output is dropped: what's left starts at the part
        let skip = Int((Double(before) / part.speed).rounded())
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: AVAudioFrameCount(chunk))!
        var out = [[Float]](repeating: [], count: 2)
        var made = 0
        while made < skip + part.length {
            let n = min(chunk, skip + part.length - made)
            guard try engine.renderOffline(AVAudioFrameCount(n), to: buffer) == .success, Int(buffer.frameLength) == n else {
                throw EngineError("the time pitch stopped")
            }
            let keep = min(n, made + n - skip)
            if keep > 0 { for c in 0..<2 { out[c] += UnsafeBufferPointer(start: buffer.floatChannelData![c] + (n - keep), count: keep) } }
            made += n
        }
        // equal-power fades into the take's own samples where it joins 1× audio of the same moment
        let a = part.joinsBefore ? min(fade, part.length / 2, part.frames / 2) : 0
        let b = part.joinsAfter ? min(fade, part.length / 2, part.frames / 2) : 0
        if a > 0 {
            let take = try Decoder(source, from: part.start).read(a)
            for c in 0..<2 { for k in 0..<a { let t = .pi / 2 * (Double(k) + 0.5) / Double(a); out[c][k] = Float(cos(t)) * take[c][k] + Float(sin(t)) * out[c][k] } }
        }
        if b > 0 {
            let take = try Decoder(source, from: part.start + part.frames - b).read(b)
            for c in 0..<2 {
                for j in 0..<b {
                    let t = .pi / 2 * (Double(j) + 0.5) / Double(b), k = part.length - b + j
                    out[c][k] = Float(cos(t)) * out[c][k] + Float(sin(t)) * take[c][j]
                }
            }
        }
        try write(to: url, frames: part.length) { try $0(out) }
        return out
    }

    /// Writes `frames` samples, given in chunks, to a file: aside first, then moved in (replacing the same render made
    /// alongside, at once), so a reader never sees half a file or none.
    static func write(to url: URL, frames: Int, _ produce: (_ out: ([[Float]]) throws -> Void) throws -> Void) throws {
        let tmp = url.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            let file = try AVAudioFile(forWriting: tmp, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
            var written = 0
            try produce { samples in
                var at = 0
                while at < samples[0].count {
                    let n = min(chunk, samples[0].count - at)
                    let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n))!
                    buffer.frameLength = AVAudioFrameCount(n)
                    for c in 0..<2 { samples[c].withUnsafeBufferPointer { buffer.floatChannelData![c].update(from: $0.baseAddress! + at, count: n) } }
                    try file.write(from: buffer)
                    at += n
                }
                written += samples[0].count
            }
            file.close()
            guard written == frames else { throw EngineError("wrote \(written) of \(frames) samples") }
        }
        guard rename(tmp.path, url.path) == 0 else { throw EngineError("can't save \(url.lastPathComponent): \(String(cString: strerror(errno)))") }
    }

    static func read(_ url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length > 0, file.processingFormat.channelCount == 2,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw EngineError("can't read \(url.lastPathComponent)") }
        try file.read(into: buffer)
        return (0..<2).map { Array(UnsafeBufferPointer(start: buffer.floatChannelData![$0], count: Int(buffer.frameLength))) }
    }

    static func hash(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined() }

    /// Removes the files starting with `prefix` that nothing has used for `after` seconds (each use touches its file),
    /// except the `keep` used last (the editor may still be playing one).
    static func prune(_ dir: URL, prefix: String, keep: Int, after: TimeInterval) {
        let old = Date().addingTimeInterval(-after)
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture) }
            .sorted { $0.1 > $1.1 }
        for (f, used) in files.dropFirst(keep) where used < old { try? FileManager.default.removeItem(at: f) }
    }

    /// A take's samples from `from` on, in order, as 48 kHz stereo: silence before the recording starts, after it ends,
    /// and from `limit` on.
    final class Decoder: @unchecked Sendable {
        private let reader: AVAssetReader
        private let output: AVAssetReaderTrackOutput
        private let limit: Int?
        private var position: Int
        /// Decoded samples from `bufferStart` on, not read yet.
        private var buffer: [[Float]] = [[], []]
        private var bufferStart: Int
        private var done = false

        init(_ source: Source, from: Int, limit: Int? = nil) throws {
            reader = try AVAssetReader(asset: source.asset)
            reader.timeRange = CMTimeRange(start: CMTime(value: Int64(max(0, from)), timescale: 48_000),
                                           end: limit.map { CMTime(value: Int64(max(0, from, $0)), timescale: 48_000) } ?? .positiveInfinity)
            output = AVAssetReaderTrackOutput(track: source.track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            ])
            reader.add(output)
            guard reader.startReading() else { throw EngineError("can't read the take's audio: \(reader.error?.localizedDescription ?? "")") }
            self.limit = limit
            position = from
            bufferStart = from
        }

        func read(_ n: Int) -> [[Float]] {
            while !done && bufferStart + buffer[0].count < position + n {
                guard let sb = output.copyNextSampleBuffer() else { done = true; break }
                guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
                let count = CMSampleBufferGetNumSamples(sb)
                var frames = [Float](repeating: 0, count: count * 2)
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 8, destination: &frames)
                // placed by time: a gap is silence, and what overlaps what's here already (a packet before `from`) is dropped
                let first = Int((sb.presentationTimeStamp.seconds * ProgramAudio.rate).rounded())
                let end = bufferStart + buffer[0].count
                if first > end { for c in 0..<2 { buffer[c] += repeatElement(0, count: first - end) } }
                let skip = max(0, end - first)
                guard skip < count else { continue }
                var left = [Float](repeating: 0, count: count - skip), right = left
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        frames.withUnsafeBytes { f in
                            var split = DSPSplitComplex(realp: l.baseAddress!, imagp: r.baseAddress!)
                            vDSP_ctoz(f.baseAddress!.assumingMemoryBound(to: DSPComplex.self) + skip, 2, &split, 1, vDSP_Length(count - skip))
                        }
                    }
                }
                buffer[0] += left; buffer[1] += right
            }
            var out = [[Float]](repeating: [Float](repeating: 0, count: n), count: 2)
            let lo = position - bufferStart
            let available = max(0, min(n, buffer[0].count - lo))
            if available > 0 { for c in 0..<2 { out[c].replaceSubrange(0..<available, with: buffer[c][lo..<lo + available]) } }
            if let limit, limit - position < n { for i in max(0, limit - position)..<n { out[0][i] = 0; out[1][i] = 0 } }
            position += n
            let drop = min(buffer[0].count, position - bufferStart)
            if drop > 0 { for c in 0..<2 { buffer[c].removeFirst(drop) }; bufferStart += drop }
            return out
        }
    }
}

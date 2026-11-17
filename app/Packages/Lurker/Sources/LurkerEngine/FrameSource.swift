import AVFoundation
import CoreVideo

/// Decoded frames of one movie, by time, sample-and-hold: the frame shown at t is the last one presented at or before t.
/// Reads forward efficiently (export) and restarts the reader for jumps (scrubbing, previews). Screen files are variable
/// frame rate, so a frame can be shown for seconds; a restart backs up far enough to find it.
final class FrameSource: @unchecked Sendable {
    let url: URL
    let size: CGSize
    let duration: Double
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var current: (t: Double, pb: CVPixelBuffer)?
    private var next: (t: Double, pb: CVPixelBuffer)?
    private var readerStart = 0.0
    private let lock = NSLock()

    init(_ url: URL) async throws {
        self.url = url
        asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let t = try await asset.loadTracks(withMediaType: .video).first else { throw EngineError("no video in \(url.lastPathComponent)") }
        track = t
        let s = try await t.load(.naturalSize)
        size = s
        duration = try await asset.load(.duration).seconds
    }

    func frame(at t: Double) -> CVPixelBuffer? {
        lock.withLock {
            let t = max(0, t)
            let have = current?.t ?? readerStart
            if reader == nil || t < have - 1e-6 || t > have + 4 { restart(at: t) }
            advance(to: t)
            // nothing presented yet at or before t (before the first frame): show the first one
            if current == nil, let n = next { return n.pb }
            return current?.pb
        }
    }

    private func advance(to t: Double) {
        if next == nil { next = read() }
        while let n = next, n.t <= t + 1e-6 {
            current = n
            next = read()
        }
    }

    private func restart(at t: Double) {
        // back up past the last keyframe (1 s apart) and a long still stretch; widen if that still lands after t
        for back in [1.5, 10, 60, Double.infinity] {
            open(from: max(0, t - back))
            if let n = next ?? read() { next = n }
            if let n = next, n.t <= t + 1e-6 { return }
            if back.isInfinite || t - back <= 0 { return }
        }
    }

    private func open(from start: Double) {
        reader?.cancelReading()
        current = nil; next = nil
        readerStart = start
        guard let r = try? AVAssetReader(asset: asset) else { reader = nil; return }
        r.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: .positiveInfinity)
        let o = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ])
        o.alwaysCopiesSampleData = false
        guard r.canAdd(o) else { reader = nil; return }
        r.add(o)
        guard r.startReading() else { reader = nil; return }
        reader = r; output = o
    }

    private func read() -> (t: Double, pb: CVPixelBuffer)? {
        while let sb = output?.copyNextSampleBuffer() {
            if let pb = sb.imageBuffer { return (sb.presentationTimeStamp.seconds, pb) }
        }
        return nil
    }
}

import AVFoundation
import CoreMedia
import VideoToolbox

/// Video codecs a take can be recorded in.
public enum CaptureCodec: String, Codable, CaseIterable, Sendable {
    /// HEVC 8-bit 4:2:0 at a generous screen-content bitrate (default: small and sharp).
    case hevc
    /// HEVC Main10 from 10-bit capture.
    case hevc10
    case h264
    /// ProRes 422 HQ: editing-grade master, large.
    case prores422hq
    /// ProRes 4444 with alpha (transparent window corners), very large.
    case prores4444

    var avCodec: AVVideoCodecType {
        switch self {
        case .hevc, .hevc10: .hevc
        case .h264: .h264
        case .prores422hq: .proRes422HQ
        case .prores4444: .proRes4444
        }
    }

    var isProRes: Bool { self == .prores422hq || self == .prores4444 }

    /// What ScreenCaptureKit should hand over for this codec.
    var pixelFormat: OSType {
        switch self {
        case .prores4444: kCVPixelFormatType_32BGRA
        case .hevc10, .prores422hq: kCVPixelFormatType_ARGB2101010LEPacked
        case .hevc, .h264: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
    }
}

/// One media file of a take: a QuickTime movie written in fragments, so a crash keeps everything up to the last second
/// or two. Every writer in a take starts its session at the take's zero, so file time t is the same instant in every
/// file. Video is variable frame rate with the real capture times; audio gaps are filled with silence so audio never
/// drifts against video.
public final class TrackWriter: @unchecked Sendable {
    public enum Kind: String, Sendable { case screen, system, mic }

    public let kind: Kind
    public let url: URL
    public let zero: CMTime
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let lock = NSLock()

    private var lastVideoPTS: CMTime?
    private var lastPixelBuffer: CVPixelBuffer?
    private var audioEnd: CMTime?
    private var audioFormat: CMAudioFormatDescription?
    private var finished = false

    public private(set) var frames = 0
    public private(set) var dropped = 0
    public private(set) var silenceFilled = 0.0
    public private(set) var sampleRate: Double?
    public private(set) var channels: Int?
    /// Gaps shorter than this are left to the decoder; longer ones get silence.
    static let audioGapTolerance = 0.03

    /// A video track. `bitrate` applies to HEVC/H.264 (bits per second).
    public init(video kind: Kind, url: URL, zero: CMTime, width: Int, height: Int, codec: CaptureCodec, fps: Double, bitrate: Double?) throws {
        self.kind = kind; self.url = url; self.zero = zero
        writer = try Self.makeWriter(url)
        var settings: [String: Any] = [AVVideoCodecKey: codec.avCodec, AVVideoWidthKey: width, AVVideoHeightKey: height]
        if !codec.isProRes {
            // screen content is sharp text on flat colour: generous bits keep edges clean
            let bps = bitrate ?? Self.screenBitrate(width: width, height: height, fps: fps, codec: codec)
            var cp: [String: Any] = [
                AVVideoAverageBitRateKey: Int(bps),
                AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
                // a keyframe every second keeps scrubbing fast and limits what a crash can lose
                AVVideoMaxKeyFrameIntervalDurationKey: 1.0,
                AVVideoAllowFrameReorderingKey: true,
            ]
            if codec == .h264 { cp[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
            if codec == .hevc10 { cp[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String }
            settings[AVVideoCompressionPropertiesKey] = cp
        }
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        try start()
    }

    /// An audio track, stored lossless (ALAC 24-bit) so later processing starts from the original.
    public init(audio kind: Kind, url: URL, zero: CMTime, channels: Int) throws {
        self.kind = kind; self.url = url; self.zero = zero
        writer = try Self.makeWriter(url)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: channels,
            AVEncoderBitDepthHintKey: 24,
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = nil
        self.channels = channels
        sampleRate = 48_000
        try start()
    }

    private static func makeWriter(_ url: URL) throws -> AVAssetWriter {
        try? FileManager.default.removeItem(at: url)
        let w = try AVAssetWriter(outputURL: url, fileType: .mov)
        // fragments: a crash loses at most the last couple of seconds; the first one lands after 1 s
        w.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
        w.initialMovieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
        return w
    }

    private func start() throws {
        guard writer.canAdd(input) else { throw CaptureError("the \(kind.rawValue) writer refused its settings") }
        writer.add(input)
        guard writer.startWriting() else { throw CaptureError("the \(kind.rawValue) writer didn't start: \(writer.error?.localizedDescription ?? "unknown")") }
        writer.startSession(atSourceTime: zero)
    }

    static func screenBitrate(width: Int, height: Int, fps: Double, codec: CaptureCodec) -> Double {
        let bpp = codec == .h264 ? 0.16 : 0.10
        return min(Double(width * height) * min(fps, 60) * bpp, codec == .h264 ? 160e6 : 120e6)
    }

    // MARK: video

    /// Appends a frame at its capture time. The first frame is also placed at zero so the file has no empty lead-in.
    @discardableResult
    public func append(_ pb: CVPixelBuffer, at pts: CMTime) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !finished, let adaptor, pts >= zero else { return false }
        if let last = lastVideoPTS {
            guard pts > last else { return false }
        } else if pts > zero + CMTime(value: 1, timescale: 1000) {
            _ = push(pb, zero, adaptor, patienceMs: 500)
        }
        return push(pb, pts, adaptor)
    }

    /// Live frames give a busy encoder (keyframes at 5K) up to 100 ms before they're dropped. The frames that pin the
    /// file's start and end aren't live and wait longer, so a loaded machine can't leave the file short.
    private func push(_ pb: CVPixelBuffer, _ pts: CMTime, _ adaptor: AVAssetWriterInputPixelBufferAdaptor, patienceMs: Int = 100) -> Bool {
        var waited = 0
        while !input.isReadyForMoreMediaData && waited < patienceMs { usleep(1000); waited += 1 }
        guard input.isReadyForMoreMediaData, adaptor.append(pb, withPresentationTime: pts) else { dropped += 1; return false }
        frames += 1
        lastVideoPTS = pts
        lastPixelBuffer = pb
        return true
    }

    // MARK: audio

    /// Appends captured audio; anything before zero is dropped and gaps get silence.
    public func append(audio sb: CMSampleBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !finished, sb.isValid, sb.numSamples > 0, let fmt = sb.formatDescription else { return }
        let pts = sb.presentationTimeStamp
        guard pts >= zero else { return }
        if audioFormat == nil { audioFormat = fmt }
        let expected = audioEnd ?? zero
        let gap = (pts - expected).seconds
        if gap > Self.audioGapTolerance { fillSilence(from: expected, to: pts) }
        guard waitForAudio(), input.append(sb) else { return }
        audioEnd = pts + sb.duration
    }

    private func waitForAudio() -> Bool {
        var waited = 0
        while !input.isReadyForMoreMediaData && waited < 200 { usleep(1000); waited += 1 }
        return input.isReadyForMoreMediaData
    }

    /// Writes digital zeros from `from` to `to` in the last seen format, in chunks of up to a second.
    private func fillSilence(from: CMTime, to: CMTime) {
        guard let fmt = audioFormat, let asbd = fmt.audioStreamBasicDescription, asbd.mFormatID == kAudioFormatLinearPCM else { return }
        var t = from
        while (to - t).seconds > 0.0005 {
            let seconds = min(1.0, (to - t).seconds)
            let frames = Int((seconds * asbd.mSampleRate).rounded())
            guard frames > 0, let sb = Self.silence(frames: frames, at: t, format: fmt, asbd: asbd), waitForAudio(), input.append(sb) else { return }
            silenceFilled += Double(frames) / asbd.mSampleRate
            t = t + CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(asbd.mSampleRate))
        }
        audioEnd = t
    }

    static func silence(frames: Int, at pts: CMTime, format: CMAudioFormatDescription, asbd: AudioStreamBasicDescription) -> CMSampleBuffer? {
        let nonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let bytes = frames * Int(asbd.mBytesPerFrame) * (nonInterleaved ? Int(asbd.mChannelsPerFrame) : 1)
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes, blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == noErr, let block,
              CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) == noErr else { return nil }
        var sb: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                                                   sampleCount: frames, presentationTimeStamp: pts, packetDescriptions: nil,
                                                                   sampleBufferOut: &sb) == noErr else { return nil }
        return sb
    }

    // MARK: finish

    public var hasMedia: Bool { lock.withLock { frames > 0 || audioEnd != nil } }

    /// Closes the file so it lasts exactly until `end`: the last frame is held, audio is padded with silence.
    /// A writer that never got media removes its file and returns false.
    @discardableResult
    public func finish(at end: CMTime) async -> Bool {
        let (ok, w, inp): (Bool, AVAssetWriter, AVAssetWriterInput) = lock.withLock {
            guard !finished else { return (false, writer, input) }
            if let pb = lastPixelBuffer, let last = lastVideoPTS, let adaptor {
                // repeat the last frame just before the end so players show it until the end
                let hold = end - CMTime(value: 1, timescale: 600)
                if hold > last { _ = push(pb, hold, adaptor, patienceMs: 2000) }
            }
            if let e = audioEnd, (end - e).seconds > 0.0005 { fillSilence(from: e, to: end) }
            finished = true
            return (frames > 0 || audioEnd != nil, writer, input)
        }
        guard ok else {
            w.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return false
        }
        inp.markAsFinished()
        w.endSession(atSourceTime: end)
        await w.finishWriting()
        return w.status == .completed
    }

    public var error: String? { writer.status == .failed ? writer.error?.localizedDescription : nil }
}

public struct CaptureError: LocalizedError, CustomStringConvertible, Sendable {
    public let description: String
    public var errorDescription: String? { description }
    public init(_ d: String) { description = d }
}

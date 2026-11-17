import AVFoundation
import CoreVideo
import Foundation
import LurkerCore
import VideoToolbox

/// Export presets (docs/rewrite-spec.md §10).
public struct ExportPreset: Sendable {
    public enum Codec: String, Sendable { case h264, hevc, prores422hq, prores4444 }
    /// 1-1-1 (BT.709 transfer, what social apps expect) or 1-13-1 (sRGB transfer, matches Safari, QuickTime and Chrome).
    public enum Tags: Sendable { case rec709, srgb }

    public var name: String
    public var codec: Codec
    public var resolution: ExportSettings.Resolution
    public var fps: Double
    /// Average bitrate, bits per second (H.264/HEVC).
    public var bitrate: Double
    public var tags: Tags
    public var audioBitrate: Int
    public var fileType: AVFileType
    public var gif: Bool = false

    public static func named(_ p: ExportSettings.Preset) -> ExportPreset {
        switch p {
        case .master: ExportPreset(name: "master", codec: .prores422hq, resolution: .native, fps: 60, bitrate: 0, tags: .srgb, audioBitrate: 0, fileType: .mov)
        case .youtube: ExportPreset(name: "youtube", codec: .h264, resolution: .p1080, fps: 60, bitrate: 20e6, tags: .srgb, audioBitrate: 320_000, fileType: .mp4)
        case .social: ExportPreset(name: "social", codec: .h264, resolution: .p1080, fps: 60, bitrate: 14e6, tags: .rec709, audioBitrate: 256_000, fileType: .mp4)
        case .x: ExportPreset(name: "x", codec: .h264, resolution: .p1080, fps: 30, bitrate: 8e6, tags: .rec709, audioBitrate: 192_000, fileType: .mp4)
        case .web: ExportPreset(name: "web", codec: .h264, resolution: .p1080, fps: 30, bitrate: 7e6, tags: .srgb, audioBitrate: 160_000, fileType: .mp4)
        case .gif: ExportPreset(name: "gif", codec: .h264, resolution: .p720, fps: 25, bitrate: 20e6, tags: .srgb, audioBitrate: 0, fileType: .mp4, gif: true)
        }
    }

    /// Bitrate scaled to the frame size and rate actually exported (preset numbers are for 1080p).
    func bitrate(for size: CGSize, fps: Double) -> Double {
        bitrate * Double(size.width * size.height) / (1920 * 1080) * max(0.6, fps / self.fps)
    }
}

/// Renders a project to a file in the background: video through the compositor, sound through the audio timeline,
/// interleaved into one writer. Deterministic, so a re-export of the same rev gives the same pixels.
public final class Exporter: @unchecked Sendable {
    public struct Result: Codable, Sendable {
        public var output: String
        public var width: Int
        public var height: Int
        public var fps: Double
        public var frames: Int
        public var duration: Double
        public var seconds: Double
        public var sizeMB: Double
        public var preset: String
    }

    private let lock = NSLock()
    private var cancelled = false
    public func cancel() { lock.withLock { cancelled = true } }
    private var isCancelled: Bool { lock.withLock { cancelled } }

    public init() {}

    public func export(bundle: ProjectBundle, project: Project? = nil, preset p: ExportPreset, to out: URL,
                       resolution: ExportSettings.Resolution? = nil, fps: Double? = nil, range: ClosedRange<Double>? = nil,
                       progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Result {
        let started = Date()
        let proj = try project ?? ProjectBundle.open(bundle.url).1.project
        let renderer = try await Renderer.open(bundle, project: proj, resolution: resolution ?? proj.export.resolution ?? p.resolution, fps: fps ?? proj.export.fps ?? p.fps)
        let size = renderer.outputSize
        let rate = renderer.look.fps
        let start = range?.lowerBound ?? 0
        let end = min(renderer.duration, range?.upperBound ?? renderer.duration)
        guard end > start else { throw EngineError("nothing to export: the program is \(String(format: "%.2f", renderer.duration)) s long") }
        let frames = Int(((end - start) * rate).rounded(.down))

        let videoURL = p.gif ? out.deletingPathExtension().appendingPathExtension("tmp.mp4") : out
        try? FileManager.default.removeItem(at: videoURL)
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        let writer = try AVAssetWriter(outputURL: videoURL, fileType: p.fileType)
        writer.shouldOptimizeForNetworkUse = p.fileType == .mp4

        let colorTags: [String: String] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: p.tags == .srgb ? AVVideoTransferFunction_IEC_sRGB : AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
        var vs: [String: Any] = [AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height), AVVideoColorPropertiesKey: colorTags]
        switch p.codec {
        case .prores422hq: vs[AVVideoCodecKey] = AVVideoCodecType.proRes422HQ
        case .prores4444: vs[AVVideoCodecKey] = AVVideoCodecType.proRes4444
        case .h264, .hevc:
            vs[AVVideoCodecKey] = p.codec == .h264 ? AVVideoCodecType.h264 : AVVideoCodecType.hevc
            var cp: [String: Any] = [
                AVVideoAverageBitRateKey: Int(p.bitrate(for: size, fps: rate)),
                AVVideoExpectedSourceFrameRateKey: Int(rate),
                AVVideoMaxKeyFrameIntervalDurationKey: 1.0,
                AVVideoAllowFrameReorderingKey: true,
            ]
            if p.codec == .h264 {
                cp[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
                cp[AVVideoH264EntropyModeKey] = AVVideoH264EntropyModeCABAC
            }
            vs[AVVideoCompressionPropertiesKey] = cp
        }
        let vin = AVAssetWriterInput(mediaType: .video, outputSettings: vs)
        vin.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vin, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ])
        guard writer.canAdd(vin) else { throw EngineError("the writer refused \(p.codec.rawValue) at \(Int(size.width))×\(Int(size.height))") }
        writer.add(vin)

        // sound: the program's audio, cut and stretched offline (the same samples the preview plays)
        var audioPump: AudioPump?
        if !p.gif {
            let timeline = try await AudioTimeline.build(proj, map: renderer.map, bundle: bundle)
            if timeline.hasAudio {
                let settings: [String: Any] = p.codec == .prores422hq || p.codec == .prores4444
                    ? [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 24,
                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
                    : [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                       // Apple's AAC encoder tops out at 320 kbps for stereo
                       AVEncoderBitRateKey: min(p.audioBitrate, 320_000)]
                let ain = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
                ain.expectsMediaDataInRealTime = false
                if writer.canAdd(ain) {
                    writer.add(ain)
                    audioPump = try AudioPump(timeline: timeline, input: ain, start: start, end: start + Double(frames) / rate)
                }
            }
        }

        guard writer.startWriting() else { throw EngineError("can't write \(out.lastPathComponent): \(writer.error?.localizedDescription ?? "")") }
        writer.startSession(atSourceTime: .zero)
        let audioDone = audioPump?.run()

        let attachments: [CFString: CFString] = [
            kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kCVImageBufferTransferFunctionKey: p.tags == .srgb ? kCVImageBufferTransferFunction_sRGB : kCVImageBufferTransferFunction_ITU_R_709_2,
            kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
        ]
        let timescale = CMTimeScale((rate * 1000).rounded())
        for i in 0..<frames {
            if isCancelled { break }
            while !vin.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            guard let pool = adaptor.pixelBufferPool else { throw EngineError("encoder has no buffer pool: \(writer.error?.localizedDescription ?? "")") }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let pb else { throw EngineError("out of frame buffers") }
            // tag the pixels with what they are so the writer doesn't convert them
            CVBufferSetAttachments(pb, attachments as CFDictionary, .shouldPropagate)
            try renderer.render(start + Double(i) / rate, into: pb, frameIndex: i)
            guard adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i) * 1000, timescale: timescale)) else {
                throw EngineError("encoder refused frame \(i): \(writer.error?.localizedDescription ?? "")")
            }
            if i % 15 == 0 { progress(Double(i) / Double(max(1, frames))) }
        }
        vin.markAsFinished()
        if isCancelled { audioPump?.cancel() }
        await audioDone?.value
        if isCancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: videoURL)
            throw EngineError("export cancelled")
        }
        await writer.finishWriting()
        if writer.status == .failed { throw EngineError("export failed: \(writer.error?.localizedDescription ?? "")") }

        var output = videoURL
        if p.gif {
            output = out.pathExtension == "gif" ? out : out.appendingPathExtension("gif")
            try GIF.make(from: videoURL, to: output, fps: p.fps, width: min(Int(size.width), 960))
            try? FileManager.default.removeItem(at: videoURL)
        }
        progress(1)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
        return Result(output: output.path, width: Int(size.width), height: Int(size.height), fps: rate, frames: frames, duration: Double(frames) / rate,
                      seconds: (Date().timeIntervalSince(started) * 10).rounded() / 10, sizeMB: (Double(bytes) / 1_048_576 * 10).rounded() / 10, preset: p.name)
    }
}

/// Feeds the program's mixed audio to the writer as it asks (interleaved with video so neither side starves).
final class AudioPump: @unchecked Sendable {
    let reader: AVAssetReader
    let output: AVAssetReaderAudioMixOutput
    let input: AVAssetWriterInput
    private let q = DispatchQueue(label: "lurker.export.audio")
    private let lock = NSLock()
    private var stopped = false
    /// Only touched on `q`.
    private var finished = false

    init(timeline: AudioTimeline, input: AVAssetWriterInput, start: Double, end: Double) throws {
        reader = try AVAssetReader(asset: timeline.composition)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 48_000), end: CMTime(seconds: end, preferredTimescale: 48_000))
        output = AVAssetReaderAudioMixOutput(audioTracks: timeline.composition.tracks(withMediaType: .audio), audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw EngineError("can't read the audio mix") }
        reader.add(output)
        self.input = input
        let startTime = start
        self.shift = CMTime(seconds: startTime, preferredTimescale: 48_000)
    }
    private let shift: CMTime

    func cancel() { lock.withLock { stopped = true } }

    func run() -> Task<Void, Never> {
        guard reader.startReading() else { input.markAsFinished(); return Task {} }
        return Task {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                input.requestMediaDataWhenReady(on: q) { [self] in
                    while input.isReadyForMoreMediaData && !finished {
                        let stop = lock.withLock { stopped }
                        guard !stop, let sb = output.copyNextSampleBuffer() else {
                            input.markAsFinished(); reader.cancelReading(); finished = true; c.resume(); return
                        }
                        // the program starts at the export's start
                        if shift == .zero { input.append(sb) }
                        else if let moved = try? CMSampleBuffer(copying: sb, withNewTiming: [CMSampleTimingInfo(duration: sb.duration,
                                                                presentationTimeStamp: sb.presentationTimeStamp - shift, decodeTimeStamp: .invalid)]) {
                            input.append(moved)
                        }
                    }
                }
            }
        }
    }
}

/// GIFs through ffmpeg's two-pass palette (a palette built from the video itself, differences dithered).
enum GIF {
    static var ffmpeg: String? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func make(from video: URL, to out: URL, fps: Double, width: Int) throws {
        guard let ff = ffmpeg else { throw EngineError("GIF export needs ffmpeg (brew install ffmpeg)") }
        // centisecond delays: 25 and 50 fps play evenly, 30 judders
        let rate = fps >= 40 ? 50 : 25
        let filter = "fps=\(rate),scale=\(width):-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ff)
        p.arguments = ["-v", "error", "-y", "-i", video.path, "-filter_complex", filter, "-loop", "0", out.path]
        let err = Pipe(); p.standardError = err
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw EngineError("ffmpeg: \(String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))")
        }
    }
}

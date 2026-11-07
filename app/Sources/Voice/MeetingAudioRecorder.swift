import AVFoundation
import ScreenCaptureKit
import CoreMedia

/// Captures **mic + system audio simultaneously** and writes a mixed mono
/// 16 kHz AAC `.m4a` file to disk via `AVAssetWriter`. Streams everything to
/// disk as it arrives so a 2-hour meeting doesn't sit in RAM.
///
/// ### Why both?
/// On a video call (Zoom / Meet / Teams), the OTHER party's audio comes
/// through your speakers (system audio) and YOUR voice goes into your mic.
/// Capturing only one side gives a half-conversation transcript.
///
/// ### System audio
/// Preferred path is a Core Audio process tap (`SystemAudioTap`, macOS
/// 14.2+), which needs only the audio-capture grant. If that's unavailable
/// or fails to set up, we fall back to ScreenCaptureKit (needs Screen
/// Recording permission).
///
/// ### Two outputs
/// - `onMicSamples` / `onSystemSamples` hand each side to the live
///   transcriber separately (that's how we label "You" vs "Them").
/// - A 100 ms flush mixes both into the master `.m4a`.
///
/// Not @MainActor: SC stream callbacks land on a background queue and
/// using a lock + dispatch keeps it simpler than hopping back to main
/// every callback.
final class MeetingAudioRecorder: NSObject, @unchecked Sendable {

    // MARK: - State

    private(set) var isRecording = false
    private(set) var outputURL: URL?

    /// True while the meeting is paused. Mic + system callbacks drop frames
    /// on the floor, so the m4a has a clean gap and the transcriber's
    /// buffers don't accumulate silence. AVAssetWriter has no native pause;
    /// this is the simplest faithful equivalent.
    var paused: Bool = false

    /// Mic samples, mono 16 kHz. Fires on AVAudioEngine's audio thread;
    /// the receiver must be thread-safe (lock + append, no main hop).
    var onMicSamples: (([Float]) -> Void)?
    /// System-audio samples, mono 16 kHz. Fires on the SCStream queue.
    var onSystemSamples: (([Float]) -> Void)?

    // MARK: - Asset writing

    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private let writeQueue = DispatchQueue(label: "com.oatmeal.meeting.write")
    private var samplesWritten: Int64 = 0
    private let targetSampleRate: Double = 16_000

    // MARK: - Capture

    private var micEngine: AVAudioEngine?
    /// `SystemAudioTap` (macOS 14.2+). Typed AnyObject because stored
    /// properties can't carry @available.
    private var systemTap: AnyObject?
    /// ScreenCaptureKit fallback when the process tap can't be set up.
    private var systemStream: SCStream?

    // MARK: - Mixing

    private var micBuffer: [Float] = []
    private var systemBuffer: [Float] = []
    private let bufferLock = NSLock()
    /// Dispatch-source timer for the 100 ms flush tick. A run-loop Timer
    /// started after `await startSystemCapture()` can land on a background
    /// thread whose run loop never runs (Dollop hit exactly this).
    private var flushTimer: DispatchSourceTimer?

    // MARK: - Public API

    /// Begin recording. Throws only if BOTH system-audio paths fail. Mic is
    /// best-effort; if mic init fails we still record system audio alone.
    func start(to url: URL) async throws {
        guard !isRecording else { return }
        outputURL = url
        samplesWritten = 0
        paused = false

        try setupAssetWriter(at: url)
        startMicCapture()       // best-effort
        do {
            try await startSystemCapture()
        } catch {
            teardownMic()
            assetWriter?.cancelWriting()
            assetWriter = nil
            audioInput = nil
            throw error
        }
        startFlushTimer()

        isRecording = true
        print("[Meeting] ▶ recording → \(url.lastPathComponent)")
    }

    /// Stop, flush remaining samples, finalize the file.
    ///
    /// Concurrency note: the tail flush and `finishWriting` both run on
    /// `writeQueue` so they can't race an in-flight append (which crashes
    /// AVAssetWriter or hangs its completion forever).
    func stop() async {
        guard isRecording else { return }
        isRecording = false
        flushTimer?.cancel()
        flushTimer = nil

        // Stop both sources first so no new samples arrive after we drain.
        if #available(macOS 14.2, *), let tap = systemTap as? SystemAudioTap {
            tap.stop()
        }
        systemTap = nil
        if let stream = systemStream {
            try? await stream.stopCapture()
            systemStream = nil
        }
        teardownMic()

        let q = writeQueue
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            q.async { [self] in
                flush()
                audioInput?.markAsFinished()
                guard let writer = assetWriter else {
                    continuation.resume()
                    return
                }
                // `finishWriting` fires its completion once the file is closed on disk.
                writer.finishWriting {
                    continuation.resume()
                }
            }
        }

        // Drop strong refs so the next start() rebuilds cleanly.
        audioInput = nil
        assetWriter = nil
        print("[Meeting] ⏹ stopped · \(samplesWritten) samples written")
    }

    // MARK: - Asset writer

    private func setupAssetWriter(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? MeetingError.writerSetup }
        writer.startSession(atSourceTime: .zero)
        assetWriter = writer
        audioInput = input
    }

    // MARK: - Mic capture

    private func startMicCapture() {
        let engine = AVAudioEngine()
        AudioInputs.apply(to: engine)   // the mic picked in Settings › Audio
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        // Defensive: AVAudioEngine throws if you install a 2nd tap on the same bus.
        input.removeTap(onBus: 0)
        // Tap at native rate, resample + mono-sum in the callback.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, !self.paused else { return }
            let samples = AudioSamples.mono16k(buffer, sourceRate: inputFormat.sampleRate)
            self.bufferLock.lock()
            self.micBuffer.append(contentsOf: samples)
            self.bufferLock.unlock()
            self.onMicSamples?(samples)
        }
        do {
            try engine.start()
            micEngine = engine
            print("[Meeting] mic running @ \(Int(inputFormat.sampleRate))Hz \(inputFormat.channelCount)ch → 16kHz mono")
        } catch {
            // Non-fatal: system audio alone is still useful.
            input.removeTap(onBus: 0)
            print("[Meeting] ✗ mic start failed: \(error.localizedDescription), continuing with system audio only")
        }
    }

    private func teardownMic() {
        guard let engine = micEngine else { return }
        // Always remove the tap; a stale tap makes the next installTap SIGABRT.
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        micEngine = nil
    }

    // MARK: - System audio capture

    private func startSystemCapture() async throws {
        if #available(macOS 14.2, *) {
            let tap = SystemAudioTap()
            do {
                try tap.start { [weak self] samples in self?.receiveSystem(samples) }
                systemTap = tap
                return
            } catch {
                print("[Meeting] process tap unavailable (\(error.localizedDescription)), falling back to ScreenCaptureKit")
            }
        }
        try await startScreenCaptureAudio()
    }

    /// Shared sink for both system-audio paths. Lock-protected; any queue.
    private func receiveSystem(_ chunk: [Float]) {
        // Drop frames while paused so the m4a has a clean gap.
        guard !paused, !chunk.isEmpty else { return }
        bufferLock.lock()
        systemBuffer.append(contentsOf: chunk)
        bufferLock.unlock()
        onSystemSamples?(chunk)
    }

    private func startScreenCaptureAudio() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                            onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw MeetingError.noDisplay }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        // Don't capture our OWN process audio (feedback loops on playback / sounds).
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(targetSampleRate)
        config.channelCount = 1
        // SCStream still requires a video config even when we only want audio.
        // Tiny resolution + 1fps minimizes overhead.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio,
                                   sampleHandlerQueue: DispatchQueue(label: "com.oatmeal.meeting.system"))
        try await stream.startCapture()
        systemStream = stream
        print("[Meeting] system audio running via ScreenCaptureKit @ 16kHz mono")
    }

    // MARK: - Mixing + write

    private func startFlushTimer() {
        let t = DispatchSource.makeTimerSource(queue: writeQueue)
        t.schedule(deadline: .now() + 0.1, repeating: 0.1)
        t.setEventHandler { [weak self] in self?.flush() }
        t.resume()
        flushTimer = t
    }

    /// Drain both buffers, average, append to the asset writer. Takes
    /// `max(mic, sys)` so we flush whenever EITHER side has audio (system
    /// is often silent while the user talks); the shorter side is padded
    /// with silence. Always runs on `writeQueue`.
    private func flush() {
        bufferLock.lock()
        let nMic = micBuffer.count
        let nSys = systemBuffer.count
        let n = max(nMic, nSys)
        guard n > 0 else { bufferLock.unlock(); return }

        var mixed = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let m = i < nMic ? micBuffer[i] : 0
            let s = i < nSys ? systemBuffer[i] : 0
            mixed[i] = (m + s) * 0.5
        }
        micBuffer.removeAll(keepingCapacity: true)
        systemBuffer.removeAll(keepingCapacity: true)
        bufferLock.unlock()

        guard let input = audioInput, input.isReadyForMoreMediaData,
              let sampleBuffer = makeSampleBuffer(from: mixed) else { return }
        if input.append(sampleBuffer) {
            samplesWritten += Int64(mixed.count)
        }
    }

    /// Build a CMSampleBuffer with a presentation timestamp matching our
    /// running sample count. We always write at exactly 16 kHz, so PTS can
    /// be derived from `samplesWritten` directly, no clock drift.
    private func makeSampleBuffer(from samples: [Float]) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: targetSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format
        )
        guard status == noErr, let format else { return nil }

        var blockBuffer: CMBlockBuffer?
        let byteCount = samples.count * MemoryLayout<Float>.size
        let bufferStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: byteCount, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: byteCount,
            flags: 0, blockBufferOut: &blockBuffer
        )
        guard bufferStatus == kCMBlockBufferNoErr, let blockBuffer else { return nil }
        _ = samples.withUnsafeBufferPointer { buf in
            CMBlockBufferReplaceDataBytes(with: buf.baseAddress!, blockBuffer: blockBuffer,
                                          offsetIntoDestination: 0, dataLength: byteCount)
        }

        let pts = CMTime(value: samplesWritten, timescale: CMTimeScale(targetSampleRate))
        var sampleBuffer: CMSampleBuffer?
        var sampleSizes = [byteCount]
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(targetSampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
            sampleCount: samples.count, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSizes,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }

    // MARK: - Errors

    enum MeetingError: Error, LocalizedError {
        case noDisplay
        case writerSetup
        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display found for system audio capture."
            case .writerSetup: return "Couldn't initialize the audio file writer."
            }
        }
    }
}

// MARK: - SCStream callbacks (system audio)

extension MeetingAudioRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        print("[Meeting] ✗ SC stream stopped: \(error.localizedDescription)")
    }
}

extension MeetingAudioRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio,
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                    lengthAtOffsetOut: nil, totalLengthOut: &length,
                                    dataPointerOut: &dataPointer)
        guard let data = dataPointer else { return }

        let floatCount = length / MemoryLayout<Float>.size
        let floatPtr = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: floatCount)
        receiveSystem(Array(UnsafeBufferPointer(start: floatPtr, count: floatCount)))
    }
}

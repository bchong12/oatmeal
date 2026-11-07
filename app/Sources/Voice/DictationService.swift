import AVFoundation
import FluidAudio

/// Hold-to-talk dictation: mic → 16 kHz buffer → the selected speech model.
///
/// ### Keeping stop() fast
/// No live partials. Instead, once the uncommitted buffer passes
/// `commitSeconds`, we cut it at the quietest point near its end and
/// transcribe that slice in the background (text lands in `liveText`).
/// So however long the user talks, `stop()` only has ≤ ~12 s of tail audio
/// left to transcribe, which Parakeet does in well under a second.
///
/// ### Level
/// The mic tap stores the latest RMS in a lock-protected box; a 30 Hz main
/// timer reads it with fast attack / slow decay so the waveform tracks the
/// voice smoothly even when AVAudioEngine hands us 100 ms buffers.
@MainActor
final class DictationService: ObservableObject {
    static let shared = DictationService()

    @Published private(set) var isListening = false
    /// Words already confirmed this session (filled by background commits on long takes)
    @Published private(set) var liveText = ""
    /// Tail still being processed (unused: no live partials)
    @Published private(set) var pendingText = ""
    /// 0...1 mic level for the waveform, updated ~30x/sec
    @Published private(set) var level: Float = 0
    /// Set when the mic won't start or sends nothing, so the pill can say so instead of showing flat waves.
    @Published private(set) var micProblem: String?
    /// State of the selected speech model (`model`).
    @Published private(set) var modelState: VoiceModelState = .notLoaded
    /// The speech model picked in Settings › Models.
    @Published private(set) var model: SpeechModel = SpeechModel.selected
    @Published private(set) var whisperVariant: WhisperVariant = WhisperVariant.selected
    /// Progress of downloads started from Settings for models other than the selected one.
    @Published private(set) var downloads: [SpeechModel: Double] = [:]
    /// Bytes on disk per model, refreshed by `refreshSizes()`.
    @Published private(set) var sizes: [SpeechModel: Int64] = [:]
    @Published private(set) var downloadError: [SpeechModel: String] = [:]
    /// Bumped on every model switch so a late load can't mark the new model ready.
    private var modelGeneration = 0

    /// Uncommitted buffer length before we transcribe a slice in the background.
    private static let commitSeconds: Double = 12
    private static let levelInterval: TimeInterval = 1.0 / 30.0

    private var engine: AVAudioEngine?
    private var configObserver: NSObjectProtocol?
    private var startedAt = Date()
    private var restarts = 0
    private let buffer = SampleBuffer()
    private let meter = LevelMeter()
    private var levelTimer: Timer?
    private var peakSeen: Float = 0
    /// Serial chain of background commits so text lands in order.
    private var commitTask: Task<Void, Never>?
    /// Bumped on every start/stop/cancel so a late commit from an old
    /// session can't write into the new one.
    private var session = 0

    private init() {
        Task {
            await AppleSpeechBackend.refreshInstalled()
            if SpeechEngine.shared.isDownloaded {
                // Model is on disk: load quietly so the first dictation is instant.
                await prepareModel()
            }
        }
    }

    // MARK: - Model

    /// Download/load the selected model if needed, updating `modelState`.
    func prepareModel() async {
        if case .ready = modelState { return }
        if case .downloading = modelState {} else { modelState = .downloading(0) }
        let generation = modelGeneration
        do {
            try await SpeechEngine.shared.load { p in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let service = DictationService.shared
                        guard service.modelGeneration == generation,
                              case .downloading(let current) = service.modelState, p > current else { return }
                        service.modelState = .downloading(p)
                    }
                }
            }
            guard generation == modelGeneration else { return }
            modelState = .ready
        } catch {
            guard generation == modelGeneration else { return }
            DFLog.log("model", "load failed: \(error.localizedDescription)")
            modelState = .failed(error.localizedDescription)
        }
        refreshSizes()
    }

    func deleteModel() async { await delete(model) }

    /// Switch speech model. Unloads the old one; loads the new one right
    /// away if it's already on disk.
    func select(_ m: SpeechModel) async {
        guard m.isSupported, m != model || modelState != .ready else { return }
        SpeechModel.selected = m
        model = m
        modelGeneration += 1
        modelState = .notLoaded
        await SpeechEngine.shared.unload()
        if SpeechEngine.shared.isDownloaded(m) { await prepareModel() }
    }

    func selectWhisperVariant(_ v: WhisperVariant) async {
        guard v != whisperVariant else { return }
        WhisperVariant.selected = v
        whisperVariant = v
        refreshSizes()
        if model == .whisper {
            modelGeneration += 1
            modelState = .notLoaded
            await SpeechEngine.shared.unload()
            if SpeechEngine.shared.isDownloaded(.whisper) { await prepareModel() }
        }
    }


    /// Download a model from Settings. The selected one is also loaded.
    func download(_ m: SpeechModel) async {
        downloadError[m] = nil
        if m == model {
            await prepareModel()
            if case .failed(let e) = modelState { downloadError[m] = e }
            return
        }
        guard downloads[m] == nil else { return }
        downloads[m] = 0
        do {
            try await SpeechEngine.shared.download(m) { p in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let service = DictationService.shared
                        if let current = service.downloads[m], p > current { service.downloads[m] = p }
                    }
                }
            }
        } catch {
            downloadError[m] = error.localizedDescription
        }
        downloads[m] = nil
        if m == .apple { await AppleSpeechBackend.refreshInstalled() }
        refreshSizes()
    }

    func delete(_ m: SpeechModel) async {
        try? await SpeechEngine.shared.delete(m)
        if m == model {
            modelGeneration += 1
            modelState = .notLoaded
        }
        refreshSizes()
    }

    /// Re-measure every model folder off the main thread.
    func refreshSizes() {
        Task.detached(priority: .utility) {
            await AppleSpeechBackend.refreshInstalled()
            var out: [SpeechModel: Int64] = [:]
            for m in SpeechModel.allCases { out[m] = SpeechEngine.modelSize(m) }
            let sizes = out
            await MainActor.run { DictationService.shared.sizes = sizes }
        }
    }

    // MARK: - Session

    /// Begin capturing the mic.
    func start() {
        guard !isListening else { return }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            DFLog.log("mic", "start refused: microphone access denied")
            micProblem = "Oatmeal can\u{2019}t use the mic. Allow it in Settings \u{203A} Audio."
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { DictationService.shared.start() }
                }
            }
            return
        default:
            break
        }

        session += 1
        buffer.removeAll()
        meter.reset()
        liveText = ""
        pendingText = ""
        level = 0
        micProblem = nil
        restarts = 0
        startedAt = Date()

        // A fresh engine can fail to start while the audio device is switching (AirPods changing
        // mode, a mic plugged in). Try once more after a beat, then with the system default mic.
        var started = startEngine(useChosenMic: true)
        if !started { Thread.sleep(forTimeInterval: 0.15); started = startEngine(useChosenMic: true) }
        if !started { started = startEngine(useChosenMic: false) }
        guard started else {
            micProblem = "The mic didn\u{2019}t start. Check Settings \u{203A} Audio."
            return
        }
        isListening = true
        watchForSilence(session)

        if modelState != .ready {
            Task { await prepareModel() }
        }
        levelTimer = Timer.scheduledTimer(withTimeInterval: Self.levelInterval, repeats: true) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DictationService.shared.tick() }
            }
        }
    }

    /// Stop, transcribe the tail, return the full transcript (trimmed).
    func stop() async -> String {
        guard isListening else { return "" }
        let mySession = session
        stopCapture()

        if modelState != .ready { await prepareModel() }

        // Grab the tail now; any background commit already drained its slice.
        let tail = buffer.drain()
        async let tailText: String = AudioSamples.hasEnergy(tail, threshold: 0.002)
            ? ((try? await SpeechEngine.shared.transcribe(tail, source: .microphone)) ?? "")
            : ""
        await commitTask?.value
        commitTask = nil
        let tailResult = await tailText
        guard mySession == session else { return "" }  // cancelled meanwhile

        let full = Self.join(liveText, tailResult)
        liveText = full
        session += 1
        DFLog.log("dictation", "transcribed \(full.count) chars")
        return full
    }

    /// Stop and throw everything away.
    func cancel() {
        guard isListening else { return }
        stopCapture()
        session += 1
        commitTask?.cancel()
        commitTask = nil
        buffer.removeAll()
        liveText = ""
        pendingText = ""
    }

    // MARK: - Internals

    private func stopCapture() {
        levelTimer?.invalidate()
        levelTimer = nil
        tearDownEngine()
        isListening = false
        let s = meter.stats()
        DFLog.log("mic", String(format: "take ended after %.1fs: %d buffers, loudest sample %.4f, peak level %.2f, %d restart(s)",
                                Date().timeIntervalSince(startedAt), s.buffers, s.rawPeak, peakSeen, restarts))
        peakSeen = 0
        level = 0
    }

    private func tearDownEngine() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        if let engine {
            // Always remove the tap; a stale tap makes the next installTap throw.
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        engine = nil
    }

    /// Builds and starts a capture engine on the chosen mic (or the system default). Logs what it got.
    @discardableResult
    private func startEngine(useChosenMic: Bool) -> Bool {
        tearDownEngine()
        let engine = AVAudioEngine()
        if useChosenMic { AudioInputs.apply(to: engine) }   // the mic picked in Settings › Audio
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let name = AVCaptureDevice.default(for: .audio)?.localizedName ?? "?"
        guard format.sampleRate > 0, format.channelCount > 0 else {
            DFLog.log("mic", "no usable input format (\(format.sampleRate) Hz, \(format.channelCount) ch); default mic \(name), chosen mic \(useChosenMic)")
            return false
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 512, format: format,
                         block: Self.makeTap(buffer: buffer, meter: meter, sourceRate: format.sampleRate))
        do {
            engine.prepare()
            try engine.start()
        } catch {
            DFLog.log("mic", "start failed: \(error.localizedDescription) (\((error as NSError).code)); \(Int(format.sampleRate)) Hz, default mic \(name), chosen mic \(useChosenMic)")
            input.removeTap(onBus: 0)
            return false
        }
        self.engine = engine
        // The device changed under us (AirPods switching to their call mic, a headset plugged in):
        // the engine stops itself and the take goes silent. Start a new one and keep going.
        // Switching to the chosen mic fires this too, a moment after start. Re-attach the same engine to
        // whatever the device is now; building a new engine would switch again and loop.
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            MainActor.assumeIsolated { DictationService.shared.reattach() }
        }
        DFLog.log("mic", "listening: \(Int(format.sampleRate)) Hz \(format.channelCount) ch, default mic \(name), chosen mic \(useChosenMic)")
        return true
    }

    /// The device under the engine changed: the engine has stopped. Put the tap back with the device's
    /// real format (the one read at start may have been the previous mic's) and start it again.
    private func reattach() {
        guard let engine else { return }
        restarts += 1
        guard restarts <= 6 else { DFLog.log("mic", "device keeps changing; giving up on this take"); return }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            DFLog.log("mic", "device changed; no usable format yet (\(format.sampleRate) Hz)"); return
        }
        input.installTap(onBus: 0, bufferSize: 512, format: format,
                         block: Self.makeTap(buffer: buffer, meter: meter, sourceRate: format.sampleRate))
        do {
            engine.prepare()
            try engine.start()
            DFLog.log("mic", "device changed; re-attached at \(Int(format.sampleRate)) Hz \(format.channelCount) ch")
        } catch {
            DFLog.log("mic", "device changed; re-attach failed: \(error.localizedDescription) (\((error as NSError).code))")
            input.removeTap(onBus: 0)
        }
    }

    private func restart(_ reason: String) {
        restarts += 1
        DFLog.log("mic", "restarting (\(reason))")
        if !startEngine(useChosenMic: true) && !startEngine(useChosenMic: false) {
            micProblem = "The mic stopped. Let go and try again."
        }
    }

    /// No buffers 0.7 s in means the mic never really started; buffers of pure zeros means a dead
    /// device. Restart once; if it's still quiet, say so on the pill.
    private func watchForSilence(_ mySession: Int) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard isListening, session == mySession else { return }
            let first = meter.stats()
            if first.buffers > 0 && first.rawPeak > 0 { return }
            DFLog.log("mic", first.buffers == 0 ? "no audio 0.7s in" : "mic sending pure silence")
            if engine != nil { reattach() } else { restart("no engine") }
            try? await Task.sleep(for: .milliseconds(900))
            guard isListening, session == mySession else { return }
            let second = meter.stats()
            if second.buffers == first.buffers || second.rawPeak == 0 {
                DFLog.log("mic", "still no sound after restart (\(second.buffers) buffers)")
                micProblem = "No sound from the mic. Check Settings \u{203A} Audio."
            }
        }
    }

    /// 30 Hz: ease the published level toward the latest mic reading, and
    /// kick off a background commit when the buffer gets long.
    private func tick() {
        guard isListening else { return }

        let target = meter.take()
        if target > peakSeen { peakSeen = target }
        // Fast attack, slow decay: reads as "moving with the voice".
        level = target > level ? target : max(target, level * 0.82)
        if level < 0.005 { level = 0 }

        guard commitTask == nil, modelState == .ready,
              Double(buffer.count) / AudioSamples.targetRate >= Self.commitSeconds else { return }
        let mySession = session
        let cut = AudioSamples.quietCutIndex(buffer.snapshot())
        let slice = buffer.drain(upTo: cut)
        commitTask = Task { [weak self] in
            let text = (try? await SpeechEngine.shared.transcribe(slice, source: .microphone)) ?? ""
            guard let self, self.session == mySession else { return }
            self.liveText = Self.join(self.liveText, text)
            self.commitTask = nil
        }
    }

    /// Built off the main actor so the tap closure isn't main-actor isolated
    /// (it runs on AVAudioEngine's render thread).
    nonisolated private static func makeTap(buffer: SampleBuffer, meter: LevelMeter, sourceRate: Double) -> AVAudioNodeTapBlock {
        return { pcm, _ in
            let samples = AudioSamples.mono16k(pcm, sourceRate: sourceRate)
            buffer.append(samples)
            // Perceptual-ish curve: quiet speech still visibly moves the bars.
            let rms = AudioSamples.rms(samples)
            // Decibels, mapped so quiet room noise sits near 0 and normal speech
            // fills most of the range (-52 dB → 0, -18 dB → 1).
            let db = 20 * log10(max(rms, 1e-6))
            meter.push(min(1, max(0, (db + 52) / 34)), raw: samples.reduce(0) { max($0, abs($1)) })
        }
    }

    private static func join(_ a: String, _ b: String) -> String {
        let a = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }
}

/// Peak-hold between UI ticks: the tap pushes readings, the 30 Hz timer
/// takes the loudest one since the last tick.
private final class LevelMeter: @unchecked Sendable {
    private var peak: Float = 0
    private var buffers = 0
    private var rawPeak: Float = 0
    private let lock = NSLock()

    func push(_ value: Float, raw: Float) {
        lock.lock()
        peak = max(peak, value)
        buffers += 1
        rawPeak = max(rawPeak, raw)
        lock.unlock()
    }

    /// Buffers the mic has delivered this take, and its loudest sample (0 = digital silence).
    func stats() -> (buffers: Int, rawPeak: Float) {
        lock.lock(); defer { lock.unlock() }
        return (buffers, rawPeak)
    }

    func take() -> Float {
        lock.lock(); defer { lock.unlock() }
        let value = peak
        // Decay instead of zeroing: AVAudioEngine often delivers ~100 ms
        // buffers, so most ticks see no fresh push.
        peak *= 0.7
        return value
    }

    func reset() {
        lock.lock(); peak = 0; buffers = 0; rawPeak = 0; lock.unlock()
    }
}

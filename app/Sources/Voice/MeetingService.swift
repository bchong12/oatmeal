import AppKit
import CoreAudio
import FluidAudio

/// Records a meeting (mic + system audio) and transcribes it live in chunks.
///
/// `MeetingAudioRecorder` writes the master `.m4a` continuously and hands
/// each side's samples to us separately. Every `chunkSeconds` we drain both
/// buffers (cut at a quiet point so words aren't split), run each through
/// Parakeet, and append `TranscriptSegment`s: mic → "You", system → "Them".
///
/// Concurrency: a single serial Task chain processes chunks, so they land
/// in order and never overlap. `stop()` drains the tail and waits for the
/// chain, so the returned recording has the whole transcript.
@MainActor
final class MeetingService: ObservableObject {
    static let shared = MeetingService()

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// Grows live during the meeting
    @Published private(set) var segments: [TranscriptSegment] = []
    /// Name of the call app currently holding the microphone ("Zoom",
    /// "Google Chrome"…), or nil. Polled every few seconds; nil while
    /// we're the ones recording.
    @Published private(set) var detectedMeetingApp: String?

    /// Seconds of audio per chunk. Short enough to feel live, long enough
    /// that Parakeet gets whole sentences to work with.
    static let chunkSeconds: Double = 8.0

    private let recorder = MeetingAudioRecorder()
    private let micBuffer = SampleBuffer()
    private let systemBuffer = SampleBuffer()
    /// Samples already handed to ASR per side, so offsets are exact in
    /// recorded (non-paused) time.
    private var micConsumed = 0
    private var systemConsumed = 0

    private var title = ""
    private var startedAt = Date()
    private var audioURL: URL?
    /// Recorded time banked before the current run (pauses excluded).
    private var bankedElapsed: TimeInterval = 0
    private var runStartedAt: Date?

    private var chunkTimer: Timer?
    private var clockTimer: Timer?
    /// Serial chain so chunks transcribe in order, never in parallel.
    private var pendingTask: Task<Void, Never>?
    private var detectTimer: Timer?

    private init() {
        detectTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { MeetingService.shared.detectMeetingApp() }
            }
        }
    }

    // MARK: - Public API

    /// Start mic + system audio capture with live transcription. Throws if
    /// ScreenCaptureKit refuses (usually Screen Recording permission).
    func start(title: String) async throws {
        guard !isRecording else { return }

        // Make sure Parakeet is on its way; chunks wait for it if needed.
        if DictationService.shared.modelState != .ready {
            Task { await DictationService.shared.prepareModel() }
        }

        micBuffer.removeAll()
        systemBuffer.removeAll()
        micConsumed = 0
        systemConsumed = 0
        segments = []
        elapsed = 0
        bankedElapsed = 0
        pendingTask = nil

        let now = Date()
        let url = Self.meetingsDirectory.appendingPathComponent("\(Self.fileStamp(now)).m4a")
        recorder.onMicSamples = Self.makeSink(micBuffer)
        recorder.onSystemSamples = Self.makeSink(systemBuffer)
        try await recorder.start(to: url)

        self.title = title
        startedAt = now
        audioURL = url
        runStartedAt = now
        isPaused = false
        isRecording = true

        chunkTimer = Timer.scheduledTimer(withTimeInterval: Self.chunkSeconds, repeats: true) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { MeetingService.shared.tick(final: false) }
            }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { MeetingService.shared.updateElapsed() }
            }
        }
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        recorder.paused = true
        if let runStartedAt { bankedElapsed += Date().timeIntervalSince(runStartedAt) }
        runStartedAt = nil
        isPaused = true
        elapsed = bankedElapsed
        // Transcribe what we have so the last words show up while paused.
        tick(final: true)
    }

    func resume() {
        guard isRecording, isPaused else { return }
        recorder.paused = false
        runStartedAt = Date()
        isPaused = false
    }

    /// Stop recording, transcribe the tail, return the finished meeting.
    func stop() async -> MeetingRecording {
        guard isRecording else {
            return MeetingRecording(title: title, startedAt: startedAt, duration: elapsed,
                                    segments: segments, audioURL: audioURL)
        }
        chunkTimer?.invalidate()
        chunkTimer = nil
        clockTimer?.invalidate()
        clockTimer = nil
        updateElapsed()
        if let runStartedAt { bankedElapsed += Date().timeIntervalSince(runStartedAt) }
        runStartedAt = nil

        await recorder.stop()
        recorder.onMicSamples = nil
        recorder.onSystemSamples = nil

        tick(final: true)
        await pendingTask?.value
        pendingTask = nil

        isRecording = false
        isPaused = false
        elapsed = bankedElapsed
        print("[Meeting] ✓ \(segments.count) segments · \(Int(elapsed))s")
        return MeetingRecording(title: title, startedAt: startedAt, duration: elapsed,
                                segments: segments, audioURL: audioURL)
    }

    // MARK: - Internals

    private func updateElapsed() {
        guard isRecording else { return }
        elapsed = bankedElapsed + (runStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// Drain both sides and queue them for transcription. `final` drains
    /// everything; otherwise we cut at a quiet point and leave the rest.
    private func tick(final: Bool) {
        let mic = drain(micBuffer, final: final)
        let sys = drain(systemBuffer, final: final)
        let micOffset = Double(micConsumed) / AudioSamples.targetRate
        let sysOffset = Double(systemConsumed) / AudioSamples.targetRate
        micConsumed += mic.count
        systemConsumed += sys.count
        guard !mic.isEmpty || !sys.isEmpty else { return }

        // Chain off the prior task so chunks run strictly in order.
        let prior = pendingTask
        pendingTask = Task { [weak self] in
            _ = await prior?.value
            await self?.processChunk(mic: mic, micOffset: micOffset, system: sys, systemOffset: sysOffset)
        }
    }

    private func drain(_ buffer: SampleBuffer, final: Bool) -> [Float] {
        if final { return buffer.drain() }
        let snapshot = buffer.snapshot()
        guard !snapshot.isEmpty else { return [] }
        return buffer.drain(upTo: AudioSamples.quietCutIndex(snapshot))
    }

    private func processChunk(mic: [Float], micOffset: TimeInterval,
                              system: [Float], systemOffset: TimeInterval) async {
        if DictationService.shared.modelState != .ready {
            await DictationService.shared.prepareModel()
        }

        // Skip silent sides; Parakeet can hallucinate a word on room tone.
        async let micText = transcribe(mic, source: .microphone)
        async let sysText = transcribe(system, source: .system)
        let you = await micText
        let them = await sysText

        var added: [TranscriptSegment] = []
        if !them.isEmpty {
            added.append(TranscriptSegment(speaker: "Them", text: them, offset: systemOffset))
        }
        // Without headphones the mic hears the speakers too. If the mic text
        // is mostly the same words as system audio, it's echo, not you.
        if !you.isEmpty && !Self.isEcho(you, of: them) {
            added.append(TranscriptSegment(speaker: "You", text: you, offset: micOffset))
        }
        guard !added.isEmpty else { return }
        segments.append(contentsOf: added.sorted { $0.offset < $1.offset })
    }

    private func transcribe(_ samples: [Float], source: AudioSource) async -> String {
        guard AudioSamples.hasEnergy(samples, threshold: 0.002) else { return "" }
        do {
            let text = try await SpeechEngine.shared.transcribe(samples, source: source)
            if AudioSamples.looksInvented(text) {
                print("[Meeting] dropped likely-invented text (\(source == .microphone ? "mic" : "system")): \(text.prefix(60))")
                return ""
            }
            return text
        } catch {
            print("[Meeting] ✗ asr failed (\(source == .microphone ? "mic" : "system")): \(error.localizedDescription)")
            return ""
        }
    }

    // MARK: - Meeting detection

    /// Bundle-id prefixes of apps that mean "you're on a call" when they
    /// hold the mic. Prefix match also catches helper processes
    /// (com.google.Chrome.helper, com.microsoft.teams2.helper…).
    private static let callApps: [(prefix: String, name: String)] = [
        ("us.zoom.xos", "Zoom"),
        ("com.microsoft.teams", "Microsoft Teams"),
        ("com.apple.FaceTime", "FaceTime"),
        ("com.cisco.webexmeetingsapp", "Webex"),
        ("Cisco-Systems.Spark", "Webex"),
        ("com.hnc.Discord", "Discord"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.google.Chrome", "Google Chrome"),
        ("com.apple.Safari", "Safari"),
        ("com.apple.WebKit", "Safari"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("com.brave.Browser", "Brave"),
        ("org.mozilla.firefox", "Firefox"),
    ]

    private func detectMeetingApp() {
        guard !isRecording else {
            if detectedMeetingApp != nil { detectedMeetingApp = nil }
            return
        }
        let found = Self.callAppUsingMic()
        if found != detectedMeetingApp { detectedMeetingApp = found }
    }

    /// Which call app is capturing audio input right now. Uses Core Audio
    /// process objects (per-process "is running input"); if those aren't
    /// available, falls back to "default mic is busy + a call app is open".
    private static func callAppUsingMic() -> String? {
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        let processes = CoreAudioProps.objectList(kAudioHardwarePropertyProcessObjectList)
        if !processes.isEmpty {
            for process in processes {
                guard CoreAudioProps.uint32(process, kAudioProcessPropertyIsRunningInput) == 1,
                      let bundle = CoreAudioProps.string(process, kAudioProcessPropertyBundleID),
                      bundle != ownBundle,
                      let match = callApps.first(where: { bundle.hasPrefix($0.prefix) }) else { continue }
                return match.name
            }
            return nil
        }

        guard let mic = CoreAudioProps.defaultDevice(kAudioHardwarePropertyDefaultInputDevice),
              CoreAudioProps.uint32(mic, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1 else { return nil }
        // Browsers are too noisy to count without per-process info.
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let nativeCallApps = callApps.prefix(6)
        for app in nativeCallApps where running.contains(where: { $0.hasPrefix(app.prefix) }) {
            return app.name
        }
        return nil
    }

    // MARK: - Helpers

    private static func isEcho(_ mic: String, of system: String) -> Bool {
        guard !system.isEmpty else { return false }
        func words(_ s: String) -> [String] {
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }
        let micWords = words(mic)
        guard !micWords.isEmpty else { return false }
        let systemWords = Set(words(system))
        let shared = micWords.filter { systemWords.contains($0) }.count
        return Double(shared) / Double(micWords.count) >= 0.6
    }

    /// Built off the main actor so the capture callback isn't main-actor isolated.
    nonisolated private static func makeSink(_ buffer: SampleBuffer) -> ([Float]) -> Void {
        return { samples in buffer.append(samples) }
    }

    static var meetingsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Oatmeal/Meetings", isDirectory: true)
    }

    private static func fileStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: date)
    }
}

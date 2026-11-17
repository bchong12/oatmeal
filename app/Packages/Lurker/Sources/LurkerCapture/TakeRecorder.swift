import AppKit
import AVFoundation
import LurkerCore
import ScreenCaptureKit

/// One take in progress: the screen stream, the input log and one crash-safe writer per track,
/// all started at the same host-clock zero. Survives locks, sleeps and stalls by pausing and reconnecting into the
/// same files; the gaps are recorded as interruptions (they become automatic cuts in the project).
public final class TakeRecorder: @unchecked Sendable {
    public enum State: String, Codable, Sendable { case recording, paused, interrupted, stopped }

    public let id: String
    public let directory: URL
    public let settings: CaptureSettings
    public let target: CaptureTarget
    public let zero: CMTime
    /// Called when the take stops itself (maxDuration).
    public var onAutoStop: (@Sendable (TakeRecorder) -> Void)?
    /// The agent's cursor, for takes recorded with `virtualCursor`.
    public private(set) var cursor: VirtualCursor?

    private let lock = NSLock()
    private var manifest: TakeManifest
    private var state = State.recording
    private let screen: ScreenStream
    private let screenWriter: TrackWriter
    private let systemWriter: TrackWriter?
    private let micWriter: TrackWriter?
    private let input: InputLog?
    private var activity: NSObjectProtocol?
    private var timer: DispatchSourceTimer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pauseStart: Double?
    private var interruption: (start: Double, reason: String)?
    private var restarts: [Double] = []
    private var reconnecting = false
    private var screenLocked = false
    private var displayAsleep = false
    private var calibrated = false
    private var lastSave = 0.0

    /// Seconds without any callback from ScreenCaptureKit before the stream counts as stalled.
    static let stallAfter = 6.0

    private init(id: String, directory: URL, settings: CaptureSettings, target: CaptureTarget, zero: CMTime, manifest: TakeManifest,
                 screen: ScreenStream, screenWriter: TrackWriter, systemWriter: TrackWriter?, micWriter: TrackWriter?,
                 input: InputLog?) {
        self.id = id; self.directory = directory; self.settings = settings; self.target = target; self.zero = zero
        self.manifest = manifest; self.screen = screen; self.screenWriter = screenWriter; self.systemWriter = systemWriter
        self.micWriter = micWriter
        self.input = input
    }

    public static func start(_ spec: TargetSpec, settings: CaptureSettings, directory: URL, id: String, name: String?) async throws -> TakeRecorder {
        try settings.validate()
        let target = try await Sources.resolve(spec, excludeSelf: settings.excludeSelf)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let zero = HostClock.now()
        let (config, w, h) = ScreenStream.configuration(target, settings)
        let screen = ScreenStream(filter: target.filter, config: config, audio: settings.systemAudio, mic: settings.microphone)
        let screenWriter = try TrackWriter(video: .screen, url: directory.appending(path: "screen.mov"), zero: zero, width: w, height: h,
                                           codec: settings.codec, fps: settings.fps, bitrate: settings.bitrateMbps.map { $0 * 1e6 })
        let systemWriter = settings.systemAudio ? try TrackWriter(audio: .system, url: directory.appending(path: "system.mov"), zero: zero, channels: 2) : nil
        let micWriter = settings.microphone ? try TrackWriter(audio: .mic, url: directory.appending(path: "mic.mov"), zero: zero, channels: 1) : nil
        let input = settings.events || settings.virtualCursor
            ? try InputLog(directory: directory, zero: zero.seconds, rect: target.rect, scale: target.pixelScale,
                           windowID: target.windowID, keys: settings.keys, virtualCursor: settings.virtualCursor) : nil

        var m = TakeManifest(id: id, name: name ?? (target.app.isEmpty ? target.kind : target.app), startedAt: Date().ISO8601Format(),
                             hostZero: zero.seconds, source: target.manifestSource)
        m.events = input == nil ? nil : "events.jsonl"
        try m.save(to: directory)

        let take = TakeRecorder(id: id, directory: directory, settings: settings, target: target, zero: zero, manifest: m, screen: screen,
                                screenWriter: screenWriter, systemWriter: systemWriter, micWriter: micWriter, input: input)
        screen.onFrame = { [weak take] pb, pts, info in take?.frame(pb, pts, info) }
        screen.onAudio = { [weak take] sb in take?.audio(sb, systemWriter) }
        screen.onMic = { [weak take] sb in take?.audio(sb, micWriter) }
        screen.onStop = { [weak take] error in take?.streamStopped(error) }
        do {
            try await screen.start()
        } catch {
            for w in [screenWriter, systemWriter, micWriter].compactMap({ $0 }) { await w.finish(at: HostClock.now()) }
            await input?.stop()
            try? FileManager.default.removeItem(at: directory)
            throw CaptureError("capture didn't start: \(error.localizedDescription)")
        }
        if settings.virtualCursor, let input {
            let z = zero.seconds
            take.cursor = VirtualCursor(start: CGPoint(x: target.rect.midX, y: target.rect.midY),
                                        log: { row, t in input.write(row, at: t) }, now: { HostClock.seconds - z })
            take.cursor?.setShape("arrow")
        }
        take.begin()
        return take
    }

    private func begin() {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical, .idleDisplaySleepDisabled], reason: "Lurker take \(id)")
        let ws = NSWorkspace.shared.notificationCenter
        let dist = DistributedNotificationCenter.default()
        func watch(_ c: NotificationCenter, _ name: Notification.Name, _ f: @escaping @Sendable (TakeRecorder) -> Void) {
            observers.append((c, c.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in if let self { f(self) } }))
        }
        watch(ws, NSWorkspace.screensDidSleepNotification) { $0.setDisplay(asleep: true) }
        watch(ws, NSWorkspace.screensDidWakeNotification) { $0.setDisplay(asleep: false) }
        watch(dist, Notification.Name("com.apple.screenIsLocked")) { $0.setLocked(true) }
        watch(dist, Notification.Name("com.apple.screenIsUnlocked")) { $0.setLocked(false) }
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    // MARK: media

    private func frame(_ pb: CVPixelBuffer, _ pts: CMTime, _ info: [SCStreamFrameInfo: Any]) {
        guard lock.withLock({ state == .recording }) else { return }
        if !calibrated {
            calibrated = true
            let arrival = HostClock.seconds
            lock.withLock {
                manifest.clock["firstFrame"] = (pts - zero).seconds
                manifest.clock["arrivalMinusPTS"] = arrival - pts.seconds
                if let ticks = (info[.displayTime] as? NSNumber)?.uint64Value {
                    manifest.clock["displayTimeMinusPTS"] = HostClock.seconds(machTicks: ticks) - pts.seconds
                }
            }
        }
        screenWriter.append(pb, at: pts)
    }

    private func audio(_ sb: CMSampleBuffer, _ writer: TrackWriter?) {
        guard let writer, lock.withLock({ state == .recording }) else { return }
        writer.append(audio: sb)
    }

    // MARK: control

    public var elapsed: Double { (HostClock.now() - zero).seconds }

    public var currentState: State { lock.withLock { state } }

    public func pause() throws {
        try lock.withLock {
            guard state == .recording else { throw CaptureError("take \(id) is \(state.rawValue), not recording") }
            state = .paused
            pauseStart = elapsed
        }
        input?.setPaused(true)
    }

    public func resume() throws {
        try lock.withLock {
            guard state == .paused, let start = pauseStart else { throw CaptureError("take \(id) isn't paused") }
            manifest.pauses.append(.init(start: start, end: elapsed, reason: "paused"))
            pauseStart = nil
            state = interruption == nil ? .recording : .interrupted
        }
        input?.setPaused(false)
    }

    @discardableResult
    public func mark(_ label: String) -> TakeManifest.Marker {
        let m = TakeManifest.Marker(t: (elapsed * 1000).rounded() / 1000, label: label)
        lock.withLock { manifest.markers.append(m) }
        input?.write(["type": "marker", "label": label], at: m.t)
        return m
    }

    /// Stops everything and closes every file at the same end time. Returns the final manifest.
    public func stop(reason: String? = nil) async -> TakeManifest {
        let alreadyStopped = lock.withLock { () -> Bool in
            if state == .stopped { return true }
            state = .stopped
            return false
        }
        if alreadyStopped { return lock.withLock { manifest } }
        timer?.cancel(); timer = nil
        let end = HostClock.now()
        let endSeconds = (end - zero).seconds
        lock.withLock {
            if let s = pauseStart { manifest.pauses.append(.init(start: s, end: endSeconds, reason: "paused")); pauseStart = nil }
            if let i = interruption { manifest.interruptions.append(.init(start: i.start, end: endSeconds, reason: i.reason)); interruption = nil }
        }
        await screen.stop()
        await input?.stop()
        async let s = screenWriter.finish(at: end)
        async let a = systemWriter?.finish(at: end)
        async let mi = micWriter?.finish(at: end)
        let (sOK, aOK, mOK) = await (s, a, mi)
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        for (center, o) in observers { center.removeObserver(o) }
        observers = []

        return lock.withLock {
            manifest.duration = endSeconds
            manifest.status = sOK ? .finished : .failed
            manifest.tracks = trackList(screenOK: sOK, systemOK: aOK ?? false, micOK: mOK ?? false)
            if !sOK { manifest.warnings.append(screenWriter.error ?? "no screen frames arrived (minimized window, or permission revoked?)") }
            if let reason { manifest.warnings.append("stopped: \(reason)") }
            try? manifest.save(to: directory)
            return manifest
        }
    }

    private func trackList(screenOK: Bool, systemOK: Bool, micOK: Bool = false) -> [TakeManifest.Track] {
        var out: [TakeManifest.Track] = []
        if screenOK {
            var t = TakeManifest.Track(kind: "screen", file: "screen.mov")
            let (w, h) = target.pixelSize(scale: settings.scale)
            t.codec = settings.codec.rawValue; t.width = w; t.height = h; t.fps = settings.fps
            t.frames = screenWriter.frames; t.dropped = screenWriter.dropped
            out.append(t)
        }
        if systemOK, let writer = systemWriter {
            var t = TakeManifest.Track(kind: writer.kind.rawValue, file: writer.url.lastPathComponent)
            t.codec = "alac"; t.sampleRate = writer.sampleRate; t.channels = writer.channels
            t.silenceFilled = (writer.silenceFilled * 1000).rounded() / 1000
            out.append(t)
        }
        if micOK, let writer = micWriter {
            var t = TakeManifest.Track(kind: writer.kind.rawValue, file: writer.url.lastPathComponent)
            t.codec = "alac"; t.sampleRate = writer.sampleRate; t.channels = writer.channels
            out.append(t)
        }
        return out
    }

    public var snapshot: TakeManifest {
        lock.withLock {
            var m = manifest
            m.duration = elapsed
            m.tracks = trackList(screenOK: true, systemOK: systemWriter != nil, micOK: micWriter != nil)
            return m
        }
    }

    public var counters: [String: Int] {
        ["frames": screenWriter.frames, "dropped": screenWriter.dropped, "idleFrames": screen.idleFrames,
         "restarts": lock.withLock { manifest.interruptions.count }]
    }

    // MARK: interruptions

    private func streamStopped(_ error: Error) {
        let (locked, asleep) = lock.withLock { (screenLocked, displayAsleep) }
        interrupted(locked ? "screen locked" : asleep ? "display asleep" : "stream stopped: \(error.localizedDescription)")
        reconnectSoon()
    }

    /// Marks the take interrupted; media arriving now is ignored until the stream is back.
    func interrupted(_ reason: String) {
        lock.withLock {
            guard state != .stopped, interruption == nil else { return }
            interruption = (elapsed, reason)
            if state == .recording { state = .interrupted }
        }
    }

    private func setLocked(_ locked: Bool) {
        lock.withLock { screenLocked = locked }
        if !locked { reconnectSoon(delay: 0.5) }
    }

    private func setDisplay(asleep: Bool) {
        lock.withLock { displayAsleep = asleep }
        if !asleep { reconnectSoon(delay: 0.5) }
    }

    /// Restarts the stream into the same files. Waits while the screen is locked or asleep; at most three tries a minute.
    private func reconnectSoon(delay: Double = 1) {
        let go = lock.withLock { () -> Bool in
            guard state != .stopped, interruption != nil, !reconnecting else { return false }
            reconnecting = true
            return true
        }
        guard go else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            while true {
                let (stopped, blocked) = self.lock.withLock { (self.state == .stopped, self.screenLocked || self.displayAsleep) }
                if stopped { break }
                if blocked { try? await Task.sleep(for: .seconds(1)); continue }
                let now = HostClock.seconds
                let recent = self.lock.withLock { self.restarts.filter { now - $0 < 60 }.count }
                if recent >= 3 { try? await Task.sleep(for: .seconds(5)); continue }
                self.lock.withLock { self.restarts.append(now) }
                await self.screen.stop()
                do {
                    try await self.screen.start()
                    self.lock.withLock {
                        if let i = self.interruption { self.manifest.interruptions.append(.init(start: i.start, end: self.elapsed, reason: i.reason)) }
                        self.interruption = nil
                        if self.state == .interrupted { self.state = .recording }
                    }
                    break
                } catch {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            self.lock.withLock { self.reconnecting = false }
        }
    }

    /// For tests: behave as if ScreenCaptureKit dropped the stream.
    public func simulateInterruption() async {
        await screen.stop()
        streamStopped(CaptureError("simulated interruption"))
    }

    /// For tests: behave as if the screen locked (the stream drops and stays down) or unlocked (it comes back).
    public func simulateLock(_ locked: Bool) async {
        setLocked(locked)
        if locked {
            await screen.stop()
            streamStopped(CaptureError("simulated lock"))
        }
    }

    private func tick() {
        let (st, since) = lock.withLock { (state, HostClock.seconds - screen.lastCallback) }
        if st == .recording, screen.running, since > Self.stallAfter {
            interrupted("stalled: no frames or audio for \(Int(since)) s")
            Task { await screen.stop(); reconnectSoon(delay: 0) }
        }
        if let max = settings.maxDuration, elapsed >= max, st != .stopped {
            Task { [weak self] in
                guard let self else { return }
                _ = await self.stop(reason: "maxDuration")
                self.onAutoStop?(self)
            }
            return
        }
        // keep take.json fresh so a crash still leaves an honest record
        if HostClock.seconds - lastSave >= 5 {
            lastSave = HostClock.seconds
            let m = snapshot
            try? m.save(to: directory)
        }
    }
}

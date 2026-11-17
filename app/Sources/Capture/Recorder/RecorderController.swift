import AppKit
import AVFoundation
import LurkerCapture
import LurkerCore

/// Screen recordings with your face and voice, Loom-style, recorded by Lurker's recorder (copied into
/// Packages/Lurker). fn ⌘ opens the start bar: pick Area, Window or Screen, your camera, mic and whether the
/// Mac's sound goes in, then Record. While recording a small bar shows the time and Pause, Start over,
/// Camera, Discard and Stop. On Stop the take is finished into a raw and a polished video (CapturePolish).
@MainActor
final class RecorderController: ObservableObject {
    static let shared = RecorderController()

    enum Mode: String, CaseIterable { case area, window, screen }
    enum Phase: Equatable { case idle, choosing, picking, recording, paused, finishing }

    @Published var mode: Mode { didSet { d.set(mode.rawValue, forKey: "recorder.mode") } }
    /// AVCaptureDevice uniqueIDs; nil = off.
    @Published var cameraID: String? { didSet { d.set(cameraID ?? "", forKey: "recorder.camera"); applyDevices() } }
    @Published var micID: String? { didSet { d.set(micID ?? "", forKey: "recorder.mic"); applyDevices() } }
    @Published var macSound: Bool { didSet { d.set(macSound, forKey: "recorder.macSound") } }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var startedAt: Date?
    /// Seconds paused so far, so the clock shows recorded time.
    @Published private(set) var pausedTotal: TimeInterval = 0
    @Published var error: String?

    let feed = CameraFeed.shared
    private let d = UserDefaults.standard
    private var take: TakeRecorder?
    private var bundle: ProjectBundle?
    private var spec: TargetSpec?
    private var targetRect: CGRect = .zero
    private var pausedAt: Date?
    private var stamp = ""

    private init() {
        mode = Mode(rawValue: d.string(forKey: "recorder.mode") ?? "") ?? .area
        let cam = d.string(forKey: "recorder.camera"), mic = d.string(forKey: "recorder.mic")
        cameraID = cam == nil ? AVCaptureDevice.default(for: .video)?.uniqueID : (cam!.isEmpty ? nil : cam)
        micID = mic == nil ? AVCaptureDevice.default(for: .audio)?.uniqueID : (mic!.isEmpty ? nil : mic)
        macSound = d.object(forKey: "recorder.macSound") as? Bool ?? false
    }

    var isRecording: Bool { phase == .recording || phase == .paused }

    /// fn ⌘: open the bar, start from it, or stop a recording.
    func toggle() {
        switch phase {
        case .idle: open()
        case .choosing: record()
        case .recording, .paused: stop()
        case .picking, .finishing: break
        }
    }

    func open() {
        guard phase == .idle else { return }
        feed.refreshDevices()
        phase = .choosing
        applyDevices()
        RecorderPanels.shared.showBar()
    }

    func close() {
        guard phase == .choosing else { return }
        phase = .idle
        RecorderPanels.shared.hideAll()
        Task { await feed.stop() }
    }

    private func applyDevices() {
        guard phase != .idle else { return }
        Task {
            await feed.use(cameraID: cameraID, micID: micID)
            RecorderPanels.shared.showBubble(feed.hasCamera)
        }
    }

    // MARK: Picking what to record

    func record() {
        guard phase == .choosing else { return }
        phase = .picking
        RecorderPanels.shared.hideBar()
        switch mode {
        case .area:
            RegionPicker.shared.pick { [weak self] rect in
                guard let self else { return }
                guard let rect, let (spec, global) = Self.regionSpec(rect) else { return self.backToChoosing() }
                self.begin(spec, rect: global)
            }
        case .window:
            WindowPicker.shared.pick { [weak self] id in
                guard let self else { return }
                guard let id, let w = WindowPicker.windows().first(where: { $0.id == id }) else { return self.backToChoosing() }
                self.begin(TargetSpec(window: Int(id)), rect: w.frame)
            }
        case .screen:
            let (id, bounds) = Self.displayUnderMouse()
            begin(TargetSpec(display: Int(id)), rect: bounds)
        }
    }

    private func backToChoosing() {
        phase = .choosing
        RecorderPanels.shared.showBar()
    }

    /// RegionPicker's box (global top-left points) as a region of the display it's on.
    static func regionSpec(_ rect: CGRect) -> (TargetSpec, CGRect)? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8), count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        guard let id = ids.prefix(Int(count)).first(where: { CGDisplayBounds($0).intersects(rect) }) else { return nil }
        let b = CGDisplayBounds(id)
        let r = rect.intersection(b)
        let region = TargetSpec.Region(x: r.minX - b.minX, y: r.minY - b.minY, width: r.width, height: r.height)
        return (TargetSpec(display: Int(id), region: region), r)
    }

    static func displayUnderMouse() -> (CGDirectDisplayID, CGRect) {
        let m = NSEvent.mouseLocation
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let p = CGPoint(x: m.x, y: mainHeight - m.y)
        var ids = [CGDirectDisplayID](repeating: 0, count: 8), count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        let id = ids.prefix(Int(count)).first { CGDisplayBounds($0).contains(p) } ?? CGMainDisplayID()
        return (id, CGDisplayBounds(id))
    }

    // MARK: Recording

    private func begin(_ spec: TargetSpec, rect: CGRect) {
        self.spec = spec
        targetRect = rect
        Task { await startTake() }
    }

    private func startTake() async {
        guard let spec else { return }
        stamp = Self.stampFormatter.string(from: Date())
        let url = CapturePolish.projects.appendingPathComponent("capture-\(stamp).lurker", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: CapturePolish.projects, withIntermediateDirectories: true)
            let b = try ProjectBundle.create(at: url)
            var s = CaptureSettings()
            s.systemAudio = macSound
            s.microphone = micID != nil
            s.microphoneID = micID
            s.keys = TextInserter.isTrusted(prompt: false)
            s.fps = 60
            let t = try await TakeRecorder.start(spec, settings: s, directory: b.takeDirectory("t1"), id: "t1", name: nil)
            bundle = b; take = t
            if feed.hasCamera { feed.startRecording(to: b.takeDirectory("t1").appending(path: "camera.mov")) }
            startedAt = Date(); pausedTotal = 0; pausedAt = nil
            phase = .recording
            RecorderPanels.shared.showControls()
            DFLog.log("recorder", "recording \(spec)")
        } catch {
            DFLog.log("recorder", "didn't start: \(error)")
            try? FileManager.default.removeItem(at: url)
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .choosing
            RecorderPanels.shared.showBar()
        }
    }

    func togglePause() {
        guard let take else { return }
        if phase == .recording {
            try? take.pause(); pausedAt = Date(); phase = .paused
        } else if phase == .paused {
            try? take.resume()
            if let p = pausedAt { pausedTotal += Date().timeIntervalSince(p) }
            pausedAt = nil; phase = .recording
        }
    }

    /// Recorded time, without pauses.
    func elapsed(at now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        let paused = pausedTotal + (pausedAt.map { now.timeIntervalSince($0) } ?? 0)
        return max(0, now.timeIntervalSince(startedAt) - paused)
    }

    func toggleCamera() {
        if cameraID == nil { cameraID = AVCaptureDevice.default(for: .video)?.uniqueID } else { cameraID = nil }
    }

    /// Throw this take away and record the same thing again.
    func startOver() {
        guard isRecording else { return }
        Task {
            await tearDown(keep: false)
            await startTake()
        }
    }

    func discard() {
        guard isRecording else { return }
        Task {
            await tearDown(keep: false)
            phase = .idle
            RecorderPanels.shared.hideAll()
            await feed.stop()
        }
    }

    func stop() {
        guard isRecording, let take, let bundle else { return }
        phase = .finishing
        RecorderPanels.shared.hideAll()
        let bubble = RecorderPanels.shared.bubbleFrame()
        let rect = targetRect, stamp = stamp
        Task {
            let manifest = await take.stop()
            let cameraURL = await feed.stopRecording()
            let cameraStart = feed.recordingStarted
            self.take = nil; self.bundle = nil
            await feed.stop()
            phase = .idle
            var camera: CapturePolish.Camera?
            if let cameraURL, let cameraStart {
                camera = .init(url: cameraURL, offset: max(0, cameraStart - manifest.hostZero), bubble: bubble, target: rect)
            }
            await CapturePolish.finish(bundle: bundle, manifest: manifest, camera: camera, stamp: stamp)
        }
    }

    private func tearDown(keep: Bool) async {
        guard let take, let bundle else { return }
        _ = await take.stop(reason: keep ? nil : "discarded")
        _ = await feed.stopRecording()
        self.take = nil; self.bundle = nil
        if !keep { try? FileManager.default.removeItem(at: bundle.url) }
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HH.mm.ss"
        return f
    }()
}

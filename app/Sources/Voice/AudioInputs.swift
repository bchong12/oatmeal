import AVFoundation
import AudioToolbox
import CoreAudio

struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// Core Audio's device UID: stable across launches and replugs, unlike the AudioDeviceID.
    let id: String
    let name: String
    let audioID: AudioDeviceID
}

/// Microphones on this Mac and the one Oatmeal listens with. "System default" follows whatever
/// macOS has selected. A picked mic sticks until it's unplugged; then the default takes over
/// until it comes back.
@MainActor
final class AudioInputs: ObservableObject {
    static let shared = AudioInputs()
    nonisolated static let key = "audio.inputUID"

    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var defaultName = ""
    /// nil = system default.
    @Published var selectedUID: String? = UserDefaults.standard.string(forKey: AudioInputs.key) {
        didSet { UserDefaults.standard.set(selectedUID, forKey: Self.key) }
    }

    private init() {
        reload()
        // Follow plugging and unplugging, and changes to the default in System Settings.
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
                MainActor.assumeIsolated { AudioInputs.shared.reload() }
            }
        }
    }

    func reload() {
        devices = Self.inputDevices()
        defaultName = Self.defaultInput().flatMap { CoreAudioProps.string($0, kAudioObjectPropertyName) } ?? "None"
    }

    /// The chosen mic isn't connected right now, so the system default is being used.
    var selectedMissing: Bool { selectedUID.map { uid in !devices.contains { $0.id == uid } } ?? false }

    /// What Oatmeal is listening with right now.
    var activeName: String {
        if let uid = selectedUID, let d = devices.first(where: { $0.id == uid }) { return d.name }
        return defaultName
    }

    // MARK: Core Audio

    nonisolated static func inputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasInput(id),
                  let uid = CoreAudioProps.string(id, kAudioDevicePropertyDeviceUID),
                  let name = CoreAudioProps.string(id, kAudioObjectPropertyName),
                  !name.hasPrefix("Oatmeal")   // our own private meeting tap
            else { return nil }
            return AudioInputDevice(id: uid, name: name, audioID: id)
        }
    }

    nonisolated static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    nonisolated static func defaultInput() -> AudioDeviceID? {
        CoreAudioProps.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
    }

    /// Points an engine's input at the chosen mic. Call before reading the input node's format.
    /// Leaves it on the system default when none is chosen or the chosen one isn't connected.
    nonisolated static func apply(to engine: AVAudioEngine) {
        guard let uid = UserDefaults.standard.string(forKey: key) else { return }
        guard let device = inputDevices().first(where: { $0.id == uid }) else {
            DFLog.log("mic", "chosen input isn't connected; using the system default"); return
        }
        guard let unit = engine.inputNode.audioUnit else { return }
        var id = device.audioID
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        DFLog.log("mic", status == noErr ? "chosen input: \(device.name)" : "couldn't switch input to \(device.name) (\(status))")
    }
}

/// Settings › Audio: listens to the chosen mic while the page is open, so you can see it hears you.
@MainActor
final class MicLevelMeter: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var problem: String?

    private var engine: AVAudioEngine?
    private var timer: Timer?
    private let box = LevelBox()

    func start() {
        stop()
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        let engine = AVAudioEngine()
        AudioInputs.apply(to: engine)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { problem = "This mic isn\u{2019}t sending any audio."; return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(box))
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            problem = "Couldn\u{2019}t open the mic: \(error.localizedDescription)"
            return
        }
        self.engine = engine
        problem = nil
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [box] _ in
            let v = box.take()
            Task { @MainActor in
                guard let meter = MicLevelMeter.current else { return }
                meter.level = max(v, meter.level * 0.8)
            }
        }
        Self.current = self
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        engine = nil
        level = 0
        if Self.current === self { Self.current = nil }
    }

    private static weak var current: MicLevelMeter?

    /// Built outside the main actor: the tap runs on Core Audio's thread.
    nonisolated private static func makeTap(_ box: LevelBox) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-6))
            box.push(min(1, max(0, (db + 55) / 40)))   // -55 dB → empty, -15 dB → full
        }
    }

    /// Loudest level since the last read, shared between the audio thread and the UI timer.
    private final class LevelBox: @unchecked Sendable {
        private let lock = NSLock()
        private var peak: Float = 0
        func push(_ v: Float) { lock.lock(); peak = max(peak, v); lock.unlock() }
        func take() -> Float { lock.lock(); defer { lock.unlock() }; let v = peak; peak = 0; return v }
    }
}

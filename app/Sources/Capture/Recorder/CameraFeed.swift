import AVFoundation
import AppKit
import LurkerCapture

/// The camera and mic for screen recordings: one capture session that feeds the camera bubble's preview,
/// records the camera to its own file while a take runs (the engine draws it as the bubble), and measures
/// the chosen mic's level for the meters. The mic itself is recorded by the take (ScreenCaptureKit).
@MainActor
final class CameraFeed: NSObject, ObservableObject {
    static let shared = CameraFeed()

    @Published private(set) var cameras: [AVCaptureDevice] = []
    @Published private(set) var mics: [AVCaptureDevice] = []
    /// 0–1, smoothed, for the level bars.
    @Published private(set) var level: Float = 0

    let session = AVCaptureSession()
    private let movie = AVCaptureMovieFileOutput()
    private let audioOut = AVCaptureAudioDataOutput()
    private var cameraInput: AVCaptureDeviceInput?
    private var micInput: AVCaptureDeviceInput?
    private let queue = DispatchQueue(label: "oatmeal.camera")
    private let levelQueue = DispatchQueue(label: "oatmeal.camera.level")
    private var recordingDone: CheckedContinuation<URL?, Never>?
    /// Host-clock seconds when the camera file started (its time 0).
    private(set) var recordingStarted: Double?

    private override init() {
        super.init()
        refreshDevices()
        session.sessionPreset = .high
        if session.canAddOutput(movie) { session.addOutput(movie) }
        audioOut.setSampleBufferDelegate(self, queue: levelQueue)
        if session.canAddOutput(audioOut) { session.addOutput(audioOut) }
    }

    func refreshDevices() {
        cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                   mediaType: .video, position: .unspecified).devices
        mics = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    }

    /// Points the session at a camera and a mic (nil = off) and starts it if either is on.
    func use(cameraID: String?, micID: String?) async {
        if cameraID != nil, AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        let camera = cameraID.flatMap { id in cameras.first { $0.uniqueID == id } ?? AVCaptureDevice.default(for: .video) }
        let mic = micID.flatMap { id in mics.first { $0.uniqueID == id } ?? AVCaptureDevice.default(for: .audio) }
        session.beginConfiguration()
        if cameraInput?.device != camera {
            if let old = cameraInput { session.removeInput(old); cameraInput = nil }
            if let camera, AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
               let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) {
                session.addInput(input); cameraInput = input
            }
        }
        if micInput?.device != mic {
            if let old = micInput { session.removeInput(old); micInput = nil }
            if let mic, let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) {
                session.addInput(input); micInput = input
            }
        }
        session.commitConfiguration()
        let run = cameraInput != nil || micInput != nil
        let s = session
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async {
                if run, !s.isRunning { s.startRunning() } else if !run, s.isRunning { s.stopRunning() }
                c.resume()
            }
        }
        if !run { level = 0 }
    }

    var hasCamera: Bool { cameraInput != nil }

    func stop() async { await use(cameraID: nil, micID: nil) }

    /// Starts writing the camera to `url`; `recordingStarted` is set once the first frame lands.
    func startRecording(to url: URL) {
        guard hasCamera else { return }
        recordingStarted = nil
        try? FileManager.default.removeItem(at: url)
        movie.startRecording(to: url, recordingDelegate: self)
    }

    /// Stops the camera file and returns it (nil if nothing was recorded).
    func stopRecording() async -> URL? {
        guard movie.isRecording else { return nil }
        return await withCheckedContinuation { c in
            recordingDone = c
            movie.stopRecording()
        }
    }
}

extension CameraFeed: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let now = HostClock.seconds
        Task { @MainActor in self.recordingStarted = now }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let ok = FileManager.default.fileExists(atPath: outputFileURL.path)
        Task { @MainActor in
            self.recordingDone?.resume(returning: ok ? outputFileURL : nil)
            self.recordingDone = nil
        }
    }
}

extension CameraFeed: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let block = CMSampleBufferGetDataBuffer(sb), let format = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { return }
        let length = CMBlockBufferGetDataLength(block)
        var data = [UInt8](repeating: 0, count: length)
        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &data)
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        var peak: Float = 0
        data.withUnsafeBytes { raw in
            if isFloat {
                for v in raw.bindMemory(to: Float.self) { peak = max(peak, abs(v)) }
            } else if asbd.mBitsPerChannel == 16 {
                for v in raw.bindMemory(to: Int16.self) { peak = max(peak, abs(Float(v) / 32768)) }
            }
        }
        // a rough loudness curve: quiet speech still moves the bars
        let shaped = min(1, sqrt(peak) * 1.3)
        Task { @MainActor in self.level = self.level * 0.6 + shaped * 0.4 }
    }
}

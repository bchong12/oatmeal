import AVFoundation
import ScreenCaptureKit

/// One ScreenCaptureKit stream: screen frames and system audio, both stamped on the host clock.
/// It can be torn down and started again (after a lock, a sleep or a stall) without the take noticing.
final class ScreenStream: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let filter: SCContentFilter
    let config: SCStreamConfiguration
    let wantsAudio: Bool
    let wantsMic: Bool

    /// Called on the screen queue with each new frame.
    var onFrame: ((CVPixelBuffer, CMTime, [SCStreamFrameInfo: Any]) -> Void)?
    var onAudio: ((CMSampleBuffer) -> Void)?
    var onMic: ((CMSampleBuffer) -> Void)?
    /// ScreenCaptureKit stopped the stream on its own (display sleep, lock, the window closed, permission revoked).
    var onStop: ((Error) -> Void)?

    private var stream: SCStream?
    private let screenQ = DispatchQueue(label: "lurker.capture.screen", qos: .userInteractive)
    private let audioQ = DispatchQueue(label: "lurker.capture.audio", qos: .userInteractive)
    private let micQ = DispatchQueue(label: "lurker.capture.mic", qos: .userInteractive)
    private let lock = NSLock()
    private var _lastCallback = 0.0
    private(set) var completeFrames = 0
    private(set) var idleFrames = 0

    /// Host seconds of the last callback of any kind (frames, idle frames, audio): the stall watchdog reads it.
    var lastCallback: Double { lock.withLock { _lastCallback } }

    init(filter: SCContentFilter, config: SCStreamConfiguration, audio: Bool, mic: Bool = false) {
        self.filter = filter; self.config = config; wantsAudio = audio; wantsMic = mic
    }

    func start() async throws {
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenQ)
        if wantsAudio { try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQ) }
        if wantsMic { try s.addStreamOutput(self, type: .microphone, sampleHandlerQueue: micQ) }
        lock.withLock { _lastCallback = HostClock.seconds }
        try await s.startCapture()
        lock.withLock { stream = s }
    }

    func stop() async {
        let s = lock.withLock { () -> SCStream? in let s = stream; stream = nil; return s }
        try? await s?.stopCapture()
    }

    var running: Bool { lock.withLock { stream != nil } }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sb.isValid else { return }
        lock.withLock { _lastCallback = HostClock.seconds }
        switch type {
        case .screen:
            guard let info = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
                  let raw = info[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { return }
            guard status == .complete, let pb = sb.imageBuffer else {
                if status == .idle { lock.withLock { idleFrames += 1 } }
                return
            }
            lock.withLock { completeFrames += 1 }
            onFrame?(pb, sb.presentationTimeStamp, info)
        case .audio: onAudio?(sb)
        case .microphone: onMic?(sb)
        default: break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let mine = lock.withLock { () -> Bool in
            guard self.stream === stream else { return false }
            self.stream = nil
            return true
        }
        if mine { onStop?(error) }
    }

    static func configuration(_ t: CaptureTarget, _ s: CaptureSettings) -> (SCStreamConfiguration, Int, Int) {
        let c = SCStreamConfiguration()
        let (w, h) = t.pixelSize(scale: s.scale)
        c.width = w; c.height = h
        if let r = t.sourceRect { c.sourceRect = r }
        // a little under the frame period so jitter never halves the frame rate
        c.minimumFrameInterval = CMTime(seconds: 0.9 / s.fps, preferredTimescale: 600_000)
        c.pixelFormat = s.codec.pixelFormat
        c.showsCursor = s.showCursor
        c.showMouseClicks = false
        c.queueDepth = 8
        c.captureResolution = .best
        c.ignoreShadowsSingleWindow = !s.windowShadow
        c.ignoreGlobalClipSingleWindow = true
        c.includeChildWindows = true
        c.shouldBeOpaque = !s.transparent
        c.capturesAudio = s.systemAudio
        c.excludesCurrentProcessAudio = s.excludeOwnAudio
        c.sampleRate = 48_000
        c.channelCount = 2
        c.captureMicrophone = s.microphone
        if s.microphone, let id = s.microphoneID { c.microphoneCaptureDeviceID = id }
        return (c, w, h)
    }
}

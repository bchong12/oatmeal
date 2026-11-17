import Foundation

/// How a take records. Every field has a default, so callers only name what they change.
public struct CaptureSettings: Codable, Equatable, Sendable {
    /// Frames per second ceiling; ScreenCaptureKit only sends frames when something changes.
    public var fps: Double = 60
    public var codec: CaptureCodec = .hevc
    /// HEVC/H.264 bitrate in Mbps; nil = automatic screen-content bitrate.
    public var bitrateMbps: Double?
    /// 0 = native Retina pixels, 1 = points.
    public var scale: Double = 0
    public var systemAudio = true
    /// Oatmeal: also record a microphone (ScreenCaptureKit's mic capture) into mic.mov.
    public var microphone = false
    /// The AVCaptureDevice uniqueID of the mic; nil = the system default.
    public var microphoneID: String?
    /// Leave our own process out of system audio (the test pattern turns this off).
    public var excludeOwnAudio = true
    /// Log mouse moves, clicks, scrolls, cursor shapes and window moves to events.jsonl.
    public var events = true
    /// Also log keystrokes (needs Accessibility).
    public var keys = false
    /// An agent drives the take: ignore the real mouse and log only the virtual cursor (VirtualCursor).
    public var virtualCursor = false
    /// Burn the real cursor into the pixels. Off by default: the renderer draws a better one from the event log.
    public var showCursor = false
    public var windowShadow = false
    /// Keep transparent corners (needs prores4444).
    public var transparent = false
    public var excludeSelf = true
    /// Seconds before the take stops itself.
    public var maxDuration: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CaptureSettings()
        fps = try c.decodeIfPresent(Double.self, forKey: .fps) ?? d.fps
        codec = try c.decodeIfPresent(CaptureCodec.self, forKey: .codec) ?? d.codec
        bitrateMbps = try c.decodeIfPresent(Double.self, forKey: .bitrateMbps)
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? d.scale
        systemAudio = try c.decodeIfPresent(Bool.self, forKey: .systemAudio) ?? d.systemAudio
        microphone = try c.decodeIfPresent(Bool.self, forKey: .microphone) ?? d.microphone
        microphoneID = try c.decodeIfPresent(String.self, forKey: .microphoneID)
        excludeOwnAudio = try c.decodeIfPresent(Bool.self, forKey: .excludeOwnAudio) ?? d.excludeOwnAudio
        events = try c.decodeIfPresent(Bool.self, forKey: .events) ?? d.events
        keys = try c.decodeIfPresent(Bool.self, forKey: .keys) ?? d.keys
        virtualCursor = try c.decodeIfPresent(Bool.self, forKey: .virtualCursor) ?? d.virtualCursor
        showCursor = try c.decodeIfPresent(Bool.self, forKey: .showCursor) ?? d.showCursor
        windowShadow = try c.decodeIfPresent(Bool.self, forKey: .windowShadow) ?? d.windowShadow
        transparent = try c.decodeIfPresent(Bool.self, forKey: .transparent) ?? d.transparent
        excludeSelf = try c.decodeIfPresent(Bool.self, forKey: .excludeSelf) ?? d.excludeSelf
        maxDuration = try c.decodeIfPresent(Double.self, forKey: .maxDuration)
    }

    public func validate() throws {
        guard fps >= 1 && fps <= 120 else { throw CaptureError("fps must be 1–120") }
        guard scale == 0 || (scale >= 0.25 && scale <= 4) else { throw CaptureError("scale is 0 (native) or 0.25–4") }
        if let b = bitrateMbps, !(b >= 1 && b <= 400) { throw CaptureError("bitrateMbps must be 1–400") }
        if transparent && codec != .prores4444 { throw CaptureError("transparent needs codec prores4444") }
        if let m = maxDuration, m <= 0 { throw CaptureError("maxDuration must be positive") }
    }
}

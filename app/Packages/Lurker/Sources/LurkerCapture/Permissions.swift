import ApplicationServices
import CoreGraphics

/// What Lurker is allowed to do right now.
public enum Permissions {
    public static func status() -> [String: String] {
        [
            "screenRecording": CGPreflightScreenCaptureAccess() ? "granted" : "missing",
            "accessibility": AXIsProcessTrusted() ? "granted" : "missing",
            "inputMonitoring": CGPreflightListenEventAccess() ? "granted" : "missing",
        ]
    }
}

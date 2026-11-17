import AppKit
import ImageIO
import LurkerCore
import ScreenCaptureKit

/// What to film, as an agent says it: one of window, app (+ title), display or region. Empty = the main display.
public struct TargetSpec: Codable, Equatable, Sendable {
    public var window: Int?
    public var app: String?
    public var title: String?
    public var display: Int?
    /// Points, top-left origin, relative to the display.
    public var region: Region?
    public struct Region: Codable, Equatable, Sendable {
        public var x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    }
    public init(window: Int? = nil, app: String? = nil, title: String? = nil, display: Int? = nil, region: Region? = nil) {
        self.window = window; self.app = app; self.title = title; self.display = display; self.region = region
    }
}

/// A resolved source: the ScreenCaptureKit filter plus where it sits on screen.
public struct CaptureTarget: @unchecked Sendable {
    public let filter: SCContentFilter
    public let kind: String
    /// Global points, top-left origin.
    public let rect: CGRect
    /// Point size of the captured content and its pixels per point.
    public let size: CGSize
    public let pixelScale: CGFloat
    public let sourceRect: CGRect?
    public let windowID: CGWindowID?
    public let displayID: CGDirectDisplayID?
    public let app: String
    public let bundleID: String?
    public let title: String
    public let pid: pid_t?

    public var manifestSource: TakeManifest.Source {
        .init(kind: kind, app: app.isEmpty ? nil : app, bundleID: bundleID, title: title.isEmpty ? nil : title,
              windowID: windowID.map { Int($0) }, displayID: displayID.map { Int($0) },
              rect: [rect.minX, rect.minY, rect.width, rect.height].map { Double($0) }, pixelScale: Double(pixelScale))
    }

    /// Output size in pixels for a scale (0 = native), even dimensions so every encoder accepts them.
    public func pixelSize(scale: Double) -> (Int, Int) {
        let mult = scale == 0 ? pixelScale : CGFloat(scale)
        return (max(2, Int((size.width * mult).rounded()) & ~1), max(2, Int((size.height * mult).rounded()) & ~1))
    }
}

public enum Sources {
    public static func content() async throws -> SCShareableContent {
        do { return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) }
        catch {
            throw CaptureError("Screen Recording permission is off for Oatmeal. Turn it on in System Settings > Privacy & Security > Screen & System Audio Recording. (\(error.localizedDescription))")
        }
    }

    static func usable(_ w: SCWindow) -> Bool {
        w.windowLayer == 0 && w.frame.width >= 80 && w.frame.height >= 60 && w.owningApplication != nil
            && w.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
    }

    public static func resolve(_ spec: TargetSpec, excludeSelf: Bool = true) async throws -> CaptureTarget {
        let c = try await content()
        func windowTarget(_ w: SCWindow) -> CaptureTarget {
            let f = SCContentFilter(desktopIndependentWindow: w)
            return CaptureTarget(filter: f, kind: "window", rect: w.frame, size: f.contentRect.size, pixelScale: CGFloat(f.pointPixelScale),
                                 sourceRect: nil, windowID: w.windowID, displayID: nil, app: w.owningApplication?.applicationName ?? "",
                                 bundleID: w.owningApplication?.bundleIdentifier, title: w.title ?? "", pid: w.owningApplication?.processID)
        }
        if let id = spec.window {
            guard let w = c.windows.first(where: { Int($0.windowID) == id }) else { throw CaptureError("no window \(id); list_sources has the current ids") }
            return windowTarget(w)
        }
        if let app = spec.app?.lowercased(), !app.isEmpty {
            let title = spec.title?.lowercased()
            let hits = c.windows.filter(usable).filter { w in
                let n = (w.owningApplication?.applicationName ?? "").lowercased(), b = (w.owningApplication?.bundleIdentifier ?? "").lowercased()
                guard n.contains(app) || b.contains(app) else { return false }
                if let title, !title.isEmpty { return (w.title ?? "").lowercased().contains(title) }
                return true
            }
            // the biggest on-screen window wins; covered windows film fine, minimized ones don't
            guard let w = hits.max(by: { ($0.isOnScreen ? 1 : 0, $0.frame.width * $0.frame.height) < ($1.isOnScreen ? 1 : 0, $1.frame.width * $1.frame.height) }) else {
                throw CaptureError("no window for app \"\(app)\"" + (title.map { " titled \"\($0)\"" } ?? "") + ". Minimized windows can't be filmed.")
            }
            return windowTarget(w)
        }
        let did = spec.display.map { CGDirectDisplayID($0) } ?? CGMainDisplayID()
        guard let d = c.displays.first(where: { $0.displayID == did }) ?? c.displays.first else { throw CaptureError("no display \(did)") }
        let me = excludeSelf ? c.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier } : []
        let f = SCContentFilter(display: d, excludingApplications: me, exceptingWindows: [])
        let scale = CGFloat(f.pointPixelScale)
        if let r = spec.region {
            let rect = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
            guard rect.width >= 16, rect.height >= 16, CGRect(origin: .zero, size: d.frame.size).contains(rect) else {
                throw CaptureError("region must be at least 16×16 points and inside display \(d.displayID) (\(Int(d.frame.width))×\(Int(d.frame.height)))")
            }
            return CaptureTarget(filter: f, kind: "region", rect: rect.offsetBy(dx: d.frame.minX, dy: d.frame.minY), size: rect.size, pixelScale: scale,
                                 sourceRect: rect, windowID: nil, displayID: d.displayID, app: "", bundleID: nil, title: "region", pid: nil)
        }
        return CaptureTarget(filter: f, kind: "display", rect: d.frame, size: d.frame.size, pixelScale: scale, sourceRect: nil,
                             windowID: nil, displayID: d.displayID, app: "", bundleID: nil, title: "display \(d.displayID)", pid: nil)
    }

    /// Displays and windows that can be filmed.
    public static func list(app: String? = nil) async throws -> [String: Any] {
        let c = try await content()
        let wins = c.windows.filter(usable).filter { $0.isOnScreen || !($0.title ?? "").isEmpty }.filter { w in
            guard let a = app?.lowercased(), !a.isEmpty else { return true }
            return (w.owningApplication?.applicationName ?? "").lowercased().contains(a) || (w.owningApplication?.bundleIdentifier ?? "").lowercased().contains(a)
        }
        func rect(_ r: CGRect) -> [String: Int] { ["x": Int(r.minX), "y": Int(r.minY), "width": Int(r.width), "height": Int(r.height)] }
        return [
            "displays": c.displays.map { ["id": Int($0.displayID), "width": $0.width, "height": $0.height, "main": $0.displayID == CGMainDisplayID(), "frame": rect($0.frame)] as [String: Any] },
            "windows": wins.map { ["id": Int($0.windowID), "app": $0.owningApplication?.applicationName ?? "", "bundleId": $0.owningApplication?.bundleIdentifier ?? "",
                                   "title": $0.title ?? "", "onScreen": $0.isOnScreen, "frame": rect($0.frame)] as [String: Any] },
        ]
    }
}

extension Sources {
    /// A still of a source as JPEG, at most `maxWidth` pixels wide (for agents to look at).
    public static func screenshot(_ spec: TargetSpec, maxWidth: Int = 1280) async throws -> (Data, CaptureTarget) {
        let t = try await resolve(spec, excludeSelf: true)
        let cfg = SCStreamConfiguration()
        let (w, h) = t.pixelSize(scale: 0)
        let k = min(1, Double(maxWidth) / Double(w))
        cfg.width = max(2, Int(Double(w) * k)); cfg.height = max(2, Int(Double(h) * k))
        if let r = t.sourceRect { cfg.sourceRect = r }
        cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = true
        let img = try await SCScreenshotManager.captureImage(contentFilter: t.filter, configuration: cfg)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { throw CaptureError("can't encode the screenshot") }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CaptureError("can't encode the screenshot") }
        return (data as Data, t)
    }
}

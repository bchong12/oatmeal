import CoreGraphics
import Foundation
import LurkerCore

/// A project's settings with every default filled in, in output pixels. The one place defaults live.
public struct Look: Sendable {
    public var outputSize: CGSize
    public var fps: Double
    public var padding: Double
    /// Corner radius in output pixels.
    public var radius: Double
    public var inset: Double
    public var shadowOpacity: Double
    public var shadowSoftness: Double
    public var shadowAngle: Double
    public var shadowDistance: Double
    public var motionBlur: Double
    public var background: JSONValue
    public var titleBar: Bool

    public var cursorHidden: Bool
    public var cursorLook: CursorStyle.Look
    public var cursorSize: Double
    public var cursorSmoothing: CursorStyle.Smoothing
    public var cursorPath: CursorStyle.Path
    public var cursorHideIdle: Double?
    public var click: CursorStyle.Click
    public var cursorMotionBlur: Double
    public var cursorLoop: Bool
    public var removeShakes: Bool


    /// Zoom moves, seconds.
    public var zoomDuration: Double = 1.0

    /// Output sizes: the resolution box's short side, turned to the canvas aspect; never upscaled past `sourceSize` for native.
    public init(_ p: Project, sourceSize: CGSize, resolution: ExportSettings.Resolution? = nil, fps: Double? = nil) {
        let aspect: Double = switch p.canvas.aspect ?? .auto {
        case .auto: Double(sourceSize.width / max(1, sourceSize.height))
        case .wide: 16.0 / 9
        case .vertical: 9.0 / 16
        case .square: 1
        case .classic: 4.0 / 3
        case .tall: 3.0 / 4
        case .portrait: 4.0 / 5
        }
        let res = resolution ?? p.export.resolution ?? .p1080
        let short: Double = switch res {
        case .native: Double(min(sourceSize.width, sourceSize.height))
        case .p480: 480
        case .p720: 720
        case .p1080: 1080
        case .p1440: 1440
        case .p2160: 2160
        }
        var w: Double, h: Double
        if res == .native && (p.canvas.aspect ?? .auto) == .auto { w = sourceSize.width; h = sourceSize.height }
        else if aspect >= 1 { h = short; w = short * aspect } else { w = short; h = short / aspect }
        outputSize = CGSize(width: Double(Int(w.rounded()) & ~1), height: Double(Int(h.rounded()) & ~1))
        self.fps = fps ?? p.export.fps ?? 60
        let k = min(outputSize.width, outputSize.height) / 1080
        padding = p.canvas.padding ?? 0.08
        radius = (p.canvas.radius ?? 16) * k
        inset = (p.canvas.inset ?? 0) * k
        shadowOpacity = p.canvas.shadow?.opacity ?? 0.35
        shadowSoftness = p.canvas.shadow?.softness ?? 0.5
        shadowAngle = p.canvas.shadow?.angle ?? 90
        shadowDistance = (p.canvas.shadow?.distance ?? 12) * k
        motionBlur = p.canvas.motionBlur ?? 0.5
        background = p.canvas.background ?? .object(["type": .string("aurora"), "name": .string("aqua")])
        titleBar = p.canvas.titleBar ?? false

        cursorHidden = p.cursor.hidden ?? false
        cursorLook = p.cursor.look ?? .macos
        cursorSize = p.cursor.size ?? 1
        cursorSmoothing = p.cursor.smoothing ?? .smooth
        cursorPath = p.cursor.path ?? .recorded
        cursorHideIdle = p.cursor.hideWhenIdleMs.flatMap { $0 > 0 ? $0 / 1000 : nil }
        click = p.cursor.click ?? .ripple
        cursorMotionBlur = p.cursor.motionBlur ?? 0.5
        cursorLoop = p.cursor.loop ?? false
        removeShakes = p.cursor.removeShakes ?? true
    }

    /// Where the screen sits on the canvas for a source of this size: inside the padding, keeping its aspect.
    public func card(source: CGSize) -> CGRect {
        let a = CGRect(origin: .zero, size: outputSize)
        let pad = padding * Double(min(a.width, a.height))
        let availW = a.width - 2 * pad, availH = a.height - 2 * pad
        let sa = Double(source.width / max(1, source.height))
        var w = availW, h = availW / sa
        if h > availH { h = availH; w = h * sa }
        return CGRect(x: a.minX + (a.width - w) / 2, y: a.minY + (a.height - h) / 2, width: w, height: h)
    }
}

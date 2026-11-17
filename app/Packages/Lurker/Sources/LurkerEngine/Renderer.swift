import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import LurkerCore
import simd

/// Draws any program time of a project. Pure in the sense that matters: the frame at t depends only on the project and
/// the media, never on frames drawn before it, so preview, export, thumbnails and agent checks all agree.
public final class Renderer: @unchecked Sendable {
    public let project: Project
    public let bundle: ProjectBundle
    public let look: Look
    public let map: TimeMap
    let compositor: Compositor
    let camera: CameraPath
    let takes: [String: TakeMedia]
    let background: MTLTexture
    let sprites: [String: (MTLTexture, CGSize, CGPoint)]
    /// Sprites are drawn this many times larger than they appear at zoom 1, so zooms keep them crisp.
    static let spriteOversample = 2.5

    struct TakeMedia {
        let id: String
        let screen: FrameSource?
        let events: EventTrack
        let cursor: CursorPath
        let sourceSize: CGSize
        /// The part of the screen frame that is shown (window title bar cut off).
        let crop: CGRect
        /// A window's own corner radius in source pixels (0 for displays and regions).
        let windowRadius: Double
        /// Oatmeal: the camera, if the take has one.
        var camera: FrameSource? = nil
        var cameraInfo: CameraInfo? = nil
    }

    /// Oatmeal's camera.json, written beside camera.mov.
    public struct CameraInfo: Codable, Sendable {
        /// Take seconds at which the camera file starts.
        public var offset: Double
        /// Centre of the bubble on the recorded screen, 0–1 of its width and height (used when there's no frame).
        public var x: Double
        public var y: Double
        /// Diameter as a share of the output height.
        public var size: Double
        public var mirror: Bool
        public init(offset: Double, x: Double, y: Double, size: Double, mirror: Bool) {
            self.offset = offset; self.x = x; self.y = y; self.size = size; self.mirror = mirror
        }
    }

    public var duration: Double { map.duration }
    public var outputSize: CGSize { look.outputSize }

    public static func open(_ bundle: ProjectBundle, project: Project? = nil, resolution: ExportSettings.Resolution? = nil, fps: Double? = nil) async throws -> Renderer {
        let p = try project ?? ProjectBundle.open(bundle.url).1.project
        var media: [String: TakeMedia] = [:]
        var firstSize: CGSize?
        for (id, take) in p.takes {
            let dir = bundle.takeDirectory(id)
            let screenURL = dir.appending(path: "screen.mov")
            let screen = FileManager.default.fileExists(atPath: screenURL.path) ? try await FrameSource(screenURL) : nil
            let size = screen?.size ?? CGSize(width: take.width ?? 1920, height: take.height ?? 1080)
            let manifest = try? TakeManifest.load(dir)
            let events = EventTrack.load(dir.appending(path: "events.jsonl"), sourceSize: size)
            var crop = CGRect(origin: .zero, size: size)
            var windowRadius = 0.0
            if manifest?.source.kind == "window", screen != nil, let frame = await WindowChrome.frame(screenURL, at: min(1, take.duration / 2)) {
                windowRadius = WindowChrome.cornerRadius(frame, scale: events.scale)
                let cut = p.canvas.titleBar ?? false ? 0 : WindowChrome.titleBarHeight(frame, scale: events.scale)
                if cut > 0 && cut < Int(size.height) / 3 { crop = CGRect(x: 0, y: Double(cut), width: size.width, height: size.height - Double(cut)) }
            }
            let lookish = Look(p, sourceSize: size)
            let cursor = CursorPath(events: events, duration: take.duration, smoothing: lookish.cursorSmoothing, removeShakes: lookish.removeShakes,
                                    hideIdle: lookish.cursorHideIdle, loop: lookish.cursorLoop, planned: lookish.cursorPath == .planned)
            var m = TakeMedia(id: id, screen: screen, events: events, cursor: cursor, sourceSize: size, crop: crop, windowRadius: windowRadius)
            let camURL = dir.appending(path: "camera.mov")
            if FileManager.default.fileExists(atPath: camURL.path),
               let data = try? Data(contentsOf: dir.appending(path: "camera.json")),
               let info = try? JSONDecoder().decode(CameraInfo.self, from: data) {
                m.camera = try? await FrameSource(camURL)
                m.cameraInfo = info
            }
            media[id] = m
            if p.clips.first?.take == id || firstSize == nil { firstSize = crop.size }
        }
        if let first = p.clips.first, let m = media[first.take] { firstSize = m.crop.size }
        let look = Look(p, sourceSize: firstSize ?? CGSize(width: 1920, height: 1080), resolution: resolution, fps: fps)
        return try Renderer(project: p, bundle: bundle, look: look, takes: media)
    }

    init(project: Project, bundle: ProjectBundle, look: Look, takes: [String: TakeMedia]) throws {
        self.project = project; self.bundle = bundle; self.look = look; self.takes = takes
        map = TimeMap(project)
        compositor = try Compositor()
        background = try compositor.texture(Backgrounds.image(look.background, size: look.outputSize))
        // cursor sprites at the size they're drawn on the first take's card, oversampled for zooms
        var sprites: [String: (MTLTexture, CGSize, CGPoint)] = [:]
        let ref = project.clips.first.flatMap { takes[$0.take] } ?? takes.values.first
        let height = Self.cursorHeight(look: look, media: ref, card: ref.map { look.card(source: $0.crop.size) })
        for (name, kind, touch) in [("arrow", CursorPath.Kind.arrow, false), ("hand", .hand, false), ("ibeam", .ibeam, false), ("dot", .arrow, true)] {
            guard let s = CursorArt.make(kind, touch: touch, heightPx: height * Self.spriteOversample) else { continue }
            let k = 1 / Self.spriteOversample
            sprites[name] = (try compositor.texture(s.image), CGSize(width: Double(s.image.width) * k, height: Double(s.image.height) * k),
                             CGPoint(x: s.hot.x * k, y: s.hot.y * k))
        }
        self.sprites = sprites
        camera = CameraPath(canvas: look.outputSize, shots: Self.shots(project, map: map, look: look, takes: takes), moveDuration: look.zoomDuration)
    }

    /// Cursor height in canvas pixels: a 19-point cursor at the recording's scale, sized onto the card.
    static func cursorHeight(look: Look, media: TakeMedia?, card: CGRect?) -> Double {
        guard let media, let card else { return 28 * look.cursorSize }
        return 19 * media.events.scale * Double(card.width / media.crop.width) * look.cursorSize
    }

    /// Zoom regions as camera shots in program time.
    static func shots(_ p: Project, map: TimeMap, look: Look, takes: [String: TakeMedia]) -> [CameraPath.Shot] {
        var out: [CameraPath.Shot] = []
        for z in p.regions.zoom {
            guard let media = takes[z.take] else { continue }
            // the program stretches that show this region (once per clip that uses it)
            var spans: [(clip: String, a: Double, b: Double)] = []
            for s in map.segments where s.take == z.take && s.sourceEnd > z.start && s.sourceStart < z.end {
                let a = s.programStart + (max(z.start, s.sourceStart) - s.sourceStart) / s.rate
                let b = s.programStart + (min(z.end, s.sourceEnd) - s.sourceStart) / s.rate
                if let last = spans.last, last.clip == s.clip, a - last.b < 1e-6 { spans[spans.count - 1].b = b } else { spans.append((s.clip, a, b)) }
            }
            for span in spans {
                let card = look.card(source: media.crop.size)
                func canvas(_ q: CGPoint) -> CGPoint {
                    CGPoint(x: card.minX + (q.x - media.crop.minX) / media.crop.width * card.width,
                            y: card.minY + (q.y - media.crop.minY) / media.crop.height * card.height)
                }
                if let x = z.x, let y = z.y {
                    let focus = canvas(CGPoint(x: media.crop.minX + x * media.crop.width, y: media.crop.minY + y * media.crop.height))
                    out.append(.init(start: span.a, end: span.b, view: CameraPath.view(canvas: look.outputSize, depth: z.depth, focus: focus), instant: z.instant ?? false))
                    continue
                }
                out += follow(span: (span.a, span.b), depth: z.depth, instant: z.instant ?? false, map: map, take: z.take, media: media, look: look, canvas: canvas)
            }
        }
        return out
    }

    /// A zoom that follows the action: it opens on its click (or where the cursor is heading), then pans only when the cursor (looked at
    /// a quarter second ahead) leaves the middle 75% of the view, at most once every 0.8 s and not in the zoom's last
    /// second, so the camera stays calm.
    static func follow(span: (Double, Double), depth: Double, instant: Bool, map: TimeMap, take: String, media: TakeMedia, look: Look,
                       canvas: (CGPoint) -> CGPoint) -> [CameraPath.Shot] {
        func cursor(_ t: Double) -> CGPoint? {
            guard let loc = map.locate(min(t, span.1)), loc.take == take, let p = media.cursor.position(at: loc.source) else { return nil }
            return canvas(p)
        }
        let size = look.outputSize
        // it opens where the action is: the first click inside it, else where the cursor spends its first second
        let click = media.events.clicks.first { c in map.program(take: take, source: c.t).contains { $0 >= span.0 && $0 <= span.1 } }
        let first = click.map { canvas(CGPoint(x: $0.x, y: $0.y)) }
            ?? (map.locate(span.0).map { media.cursor.focus(from: $0.source, to: $0.source + 1) } ?? nil).map(canvas)
            ?? cursor(span.0) ?? CGPoint(x: size.width / 2, y: size.height / 2)
        var view = CameraPath.view(canvas: size, depth: depth, focus: first)
        var shots = [CameraPath.Shot(start: span.0, end: span.1, view: view, instant: instant)]
        var lastPan = span.0
        var t = span.0 + 0.1
        // no pan in a zoom's last second: a pan straight into the zoom-out reads as a jolt
        while t < span.1 - 1.0 {
            if let c = cursor(t + 0.25), t - lastPan >= 0.8 {
                let safe = view.insetBy(dx: view.width * 0.125, dy: view.height * 0.125)
                if !safe.contains(c) {
                    view = CameraPath.view(canvas: size, depth: depth, focus: c)
                    shots[shots.count - 1].end = t
                    shots.append(.init(start: t, end: span.1, view: view))
                    lastPan = t
                }
            }
            t += 0.1
        }
        return shots
    }

    // MARK: drawing

    /// Renders program time t into a BGRA pixel buffer of `outputSize`.
    public func render(_ t: Double, into out: CVPixelBuffer, frameIndex: Int = 0) throws {
        var u = FrameUniforms()
        let W = Float(look.outputSize.width), H = Float(look.outputSize.height)
        u.outSize = .init(W, H); u.canvasSize = .init(W, H)
        u.frameIndex = Float(frameIndex % 64)
        let shutter = look.motionBlur * 0.5 / look.fps
        let v0 = camera.view(at: t - shutter / 2), v1 = camera.view(at: t + shutter / 2)
        u.view0 = Self.vec(v0); u.view1 = Self.vec(v1)
        // samples by how far the picture slides during the shutter, in output pixels
        let slide = max(abs(v0.minX - v1.minX), abs(v0.maxX - v1.maxX), abs(v0.minY - v1.minY), abs(v0.maxY - v1.maxY)) * Double(W) / Double(max(1, v0.width))
        u.blurSamples = Int32(min(16, max(1, Int(slide / 1.5))))

        guard let loc = map.locate(t), let media = takes[loc.take] else {
            u.screenOn = 0
            try compositor.render(into: out, uniforms: u, cursorPositions: [], source: nil, background: background, cursor: nil)
            return
        }
        let s = loc.source
        let card = look.card(source: media.crop.size)
        u.card = Self.vec(card)
        u.crop = Self.vec(media.crop)
        u.srcSize = .init(Float(media.sourceSize.width), Float(media.sourceSize.height))
        // at least as round as the window's own corners, or their fill shows
        let windowRadius = media.windowRadius * Double(card.width / media.crop.width)
        u.radius = Float(min(max(look.radius, windowRadius), Double(min(card.width, card.height)) / 2))
        let k = look.outputSize.height / 1080
        let a = look.shadowAngle * .pi / 180
        u.shadow = .init(Float(cos(a) * look.shadowDistance), Float(sin(a) * look.shadowDistance), Float((6 + look.shadowSoftness * 40) * k), Float(look.shadowOpacity))
        if look.inset > 0 { u.inset = .init(0.08, 0.08, 0.09, Float(look.inset)) }

        // cursor: sub-frame positions along its real path for motion blur
        var cursorPositions: [SIMD2<Float>] = []
        var spriteTex: MTLTexture?
        if !look.cursorHidden, !media.cursor.isEmpty {
            let alpha = media.cursor.alpha(at: s)
            let name = look.cursorLook == .touch ? "dot" : media.cursor.kind(at: s).rawValue
            if alpha > 0.001, let (tex, size, hot) = sprites[name] {
                let cs = look.cursorMotionBlur * 0.5 / look.fps
                func canvasPoint(_ p: CGPoint) -> SIMD2<Float> {
                    .init(Float(card.minX + (p.x - media.crop.minX) / media.crop.width * card.width),
                          Float(card.minY + (p.y - media.crop.minY) / media.crop.height * card.height))
                }
                let first = map.locate(t - cs / 2).flatMap { $0.take == loc.take ? media.cursor.position(at: $0.source) : nil }
                let last = map.locate(t + cs / 2).flatMap { $0.take == loc.take ? media.cursor.position(at: $0.source) : nil }
                var m = 1
                if let first, let last {
                    let d = simd_distance(canvasPoint(first), canvasPoint(last)) * W / Float(v0.width)
                    m = min(16, max(1, Int(d / 2)))
                }
                for i in 0..<m {
                    let f = m == 1 ? 0.5 : (Double(i) + 0.5) / Double(m)
                    let tt = t + (f - 0.5) * cs
                    let ss = map.locate(tt).flatMap { $0.take == loc.take ? $0.source : nil } ?? s
                    if let p = media.cursor.position(at: ss) { cursorPositions.append(canvasPoint(p)) }
                }
                let scale = Double(card.width / media.crop.width) / Double(look.outputSize.width / max(1, look.outputSize.width))
                _ = scale
                u.cursor = .init(Float(size.width), Float(size.height), Float(hot.x), Float(hot.y))
                u.cursorSamples = Int32(cursorPositions.count)
                u.cursorAlpha = Float(alpha)
                u.cursorOn = cursorPositions.isEmpty ? 0 : 1
                spriteTex = tex
            }
            if look.click != .none, let (c, age) = media.cursor.click(at: s, window: 0.45) {
                let e = 1 - pow(1 - age / 0.45, 3)
                let pt = media.events.scale * Double(card.width / media.crop.width)
                let p = CGPoint(x: card.minX + (c.x - media.crop.minX) / media.crop.width * card.width,
                                y: card.minY + (c.y - media.crop.minY) / media.crop.height * card.height)
                u.ripple = .init(Float(p.x), Float(p.y), Float((7 + 24 * e) * pt), Float((1 - age / 0.45) * 0.55))
            }
        }

        let frame = media.screen?.frame(at: s)
        let masks = maskUniforms(take: loc.take, at: s, media: media)
        u.maskCount = Int32(masks.count)
        u.highlightCount = Int32(masks.filter { $0.kind == 3 }.count)
        // Oatmeal: the camera bubble. Framed (padding) puts it in the bottom-left corner of the output; unframed keeps it
        // where it was on the screen.
        var camFrame: CVPixelBuffer?
        if let cam = media.camera, let info = media.cameraInfo, s >= info.offset, let pb = cam.frame(at: s - info.offset) {
            let r = info.size * Double(H) / 2
            let c: CGPoint = look.padding > 0
                ? CGPoint(x: Double(H) * 0.05 + r, y: Double(H) * 0.95 - r)
                : CGPoint(x: card.minX + info.x * card.width, y: card.minY + info.y * card.height)
            u.cam = .init(Float(c.x), Float(c.y), Float(r), info.mirror ? 1 : 0)
            u.camSize = .init(Float(CVPixelBufferGetWidth(pb)), Float(CVPixelBufferGetHeight(pb)))
            u.camOn = 1
            camFrame = pb
        }
        try compositor.render(into: out, uniforms: u, cursorPositions: cursorPositions, source: frame, background: background,
                              cursor: spriteTex, masks: masks, camera: camFrame)
    }

    /// Masks active at source time s, in source pixels; scroll-tracked masks move with the page.
    func maskUniforms(take: String, at s: Double, media: TakeMedia) -> [MaskUniform] {
        project.regions.mask.filter { $0.take == take && s >= $0.start && s < $0.end && $0.rect.count == 4 }.prefix(8).map { m in
            var y = m.rect[1] * media.sourceSize.height
            if m.track == .scroll {
                // content moves by the scroll distance (points → source pixels)
                y += media.events.scrolled(from: m.start, to: s) * media.events.scale
            }
            let r = SIMD4<Float>(Float(m.rect[0] * media.sourceSize.width), Float(y), Float(m.rect[2] * media.sourceSize.width), Float(m.rect[3] * media.sourceSize.height))
            let kind: Int32 = switch m.effect { case .blur: 0; case .pixelate: 1; case .redact: 2; case .highlight: 3 }
            return MaskUniform(rect: r, kind: kind)
        }
    }

    static func vec(_ r: CGRect) -> SIMD4<Float> { .init(Float(r.minX), Float(r.minY), Float(r.width), Float(r.height)) }

    // MARK: stills

    /// A pixel buffer of the output size, ready to render into (previews keep a few and reuse them).
    public func makeFrameBuffer() throws -> CVPixelBuffer { try makeBuffer(look.outputSize) }

    func makeBuffer(_ size: CGSize) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any], kCVPixelBufferMetalCompatibilityKey as String: true]
        guard CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess, let pb else {
            throw EngineError("can't make a \(Int(size.width))×\(Int(size.height)) frame")
        }
        return pb
    }

    /// One frame as an image.
    public func image(at t: Double) throws -> CGImage {
        let pb = try makeBuffer(look.outputSize)
        try render(t, into: pb)
        let ci = CIImage(cvPixelBuffer: pb)
        guard let img = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()]).createCGImage(ci, from: ci.extent, format: .BGRA8,
                                                                                                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw EngineError("can't read the frame back")
        }
        return img
    }
}

extension CursorPath {
    /// Where the cursor spends its time between two source times (time-weighted), for aiming a zoom.
    func focus(from a: Double, to b: Double) -> CGPoint? {
        guard !isEmpty, b > a else { return position(at: a) }
        var sx = 0.0, sy = 0.0, n = 0.0
        var t = a
        while t <= b {
            if let p = position(at: t) { sx += p.x; sy += p.y; n += 1 }
            t += 0.05
        }
        return n > 0 ? CGPoint(x: sx / n, y: sy / n) : nil
    }
}

/// Window takes come with the window's own chrome: its title bar (cut off unless canvas.titleBar) and its rounded corners,
/// which arrive filled in. Both are measured on one frame.
enum WindowChrome {
    static func frame(_ url: URL, at t: Double) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .positiveInfinity
        return try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    }

    /// RGBA bytes of part of an image (top row first).
    static func pixels(_ cg: CGImage, _ r: CGRect) -> (data: [UInt8], width: Int)? {
        let w = Int(r.width), h = Int(r.height)
        guard w > 0, h > 0, let part = cg.cropping(to: r) else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w)
    }

    /// Title bar height in pixels: the strongest full-width edge in the top 60 points.
    static func titleBarHeight(_ cg: CGImage, scale: Double) -> Int {
        let w = cg.width, rows = min(cg.height / 4, Int(60 * scale))
        guard rows > Int(16 * scale) + 2, let (data, _) = pixels(cg, CGRect(x: 0, y: 0, width: w, height: rows + 1)) else { return 0 }
        func px(_ r: Int, _ x: Int) -> (Int, Int, Int) { let o = r * w * 4 + x * 4; return (Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) }
        var best = 0, bestScore = 0.0
        var scores: [Int: Double] = [:]
        for r in Int(16 * scale)..<rows {
            var hits = 0, n = 0
            for x in stride(from: 0, to: w, by: 4) {
                let a = px(r - 1, x), b = px(r, x)
                if abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) > 30 { hits += 1 }
                n += 1
            }
            let score = Double(hits) / Double(max(1, n))
            scores[r] = score
            if score > bestScore { bestScore = score; best = r }
        }
        guard bestScore > 0.85 else { return 0 }
        let below = (best + 1...best + Int(4 * scale)).filter { (scores[$0] ?? 0) > 0.85 }
        return (below.last ?? best) & ~1
    }

    /// Radius of the window's bottom corners in pixels. Walking in from a corner along the diagonal, the corner's fill
    /// gives way to the window where a round corner of radius r crosses it, r·(1 − 1/√2) in. Nothing in the fill can
    /// stop the walk early, so the smaller of the two corners is the answer; 0 when the fill runs on into the window
    /// (same colour, and nothing shows anyway).
    static func cornerRadius(_ cg: CGImage, scale: Double) -> Double {
        let n = min(Int(40 * scale), cg.width / 4, cg.height / 4)
        guard n > 4 else { return 0 }
        func walk(fromLeft: Bool) -> Int? {
            let x0 = fromLeft ? 0 : cg.width - n
            guard let (data, w) = pixels(cg, CGRect(x: x0, y: cg.height - n, width: n, height: n)) else { return nil }
            func px(_ r: Int, _ x: Int) -> (Int, Int, Int) { let o = r * w * 4 + x * 4; return (Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) }
            let corner = px(n - 1, fromLeft ? 0 : n - 1)
            for i in 1..<n {
                let p = px(n - 1 - i, fromLeft ? i : n - 1 - i)
                if abs(p.0 - corner.0) + abs(p.1 - corner.1) + abs(p.2 - corner.2) > 48 { return i }
            }
            return nil
        }
        guard let i = [walk(fromLeft: true), walk(fromLeft: false)].compactMap({ $0 }).min() else { return 0 }
        // macOS draws continuous corners, which start curving further out than a circle through the same point
        return Double(i) / (1 - 1 / 2.0.squareRoot()) * continuousCorner
    }

    /// How much rounder than the measured circle the card has to be to cover a continuous corner's fill.
    static let continuousCorner = 1.25
}

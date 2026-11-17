import CoreGraphics
import Foundation

/// Lurker's own cursors, drawn as vectors at exactly the size needed so they stay sharp at any zoom.
/// (Never Apple's cursor artwork.) Arrow, pointing hand and I-beam on a 20-unit grid; a soft dot for touch style.
enum CursorArt {
    struct Sprite { let image: CGImage; let hot: CGPoint }

    static func make(_ kind: CursorPath.Kind, touch: Bool, heightPx: CGFloat) -> Sprite? {
        if touch { return dot(heightPx: heightPx) }
        switch kind {
        case .arrow: return arrow(heightPx: heightPx)
        case .hand: return hand(heightPx: heightPx)
        case .ibeam: return ibeam(heightPx: heightPx * 0.9)
        }
    }

    private static func context(_ w: Int, _ h: Int) -> CGContext? {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        // draw top-left down, like the grids below
        ctx?.translateBy(x: 0, y: CGFloat(h)); ctx?.scaleBy(x: 1, y: -1)
        return ctx
    }

    static let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    /// A soft shadow under every shape, a white outline, a black fill.
    private static func paint(_ ctx: CGContext, _ path: CGPath, u: CGFloat, join: CGLineJoin = .round) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -0.5 * u), blur: 1.6 * u, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        ctx.addPath(path); ctx.setStrokeColor(white); ctx.setLineWidth(2.6 * u); ctx.setLineJoin(join); ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(path); ctx.setFillColor(black); ctx.fillPath()
    }

    static func arrow(heightPx: CGFloat) -> Sprite? {
        let u = heightPx / 20, m = 3 * u
        let pts: [CGPoint] = [.init(x: 0, y: 0), .init(x: 0, y: 16.6), .init(x: 3.9, y: 12.9), .init(x: 6.6, y: 19.3), .init(x: 9.4, y: 18.2),
                              .init(x: 6.7, y: 11.9), .init(x: 12.0, y: 11.9)]
        let w = Int((12.2 * u + 2 * m).rounded(.up)), h = Int((19.6 * u + 2 * m).rounded(.up))
        guard let ctx = context(w, h) else { return nil }
        let path = CGMutablePath()
        path.addLines(between: pts.map { CGPoint(x: m + $0.x * u, y: m + $0.y * u) }); path.closeSubpath()
        paint(ctx, path, u: u, join: .miter)
        return ctx.makeImage().map { Sprite(image: $0, hot: CGPoint(x: m, y: m)) }
    }

    /// A pointing hand: the index finger up, three folded fingers, the thumb along the side.
    static func hand(heightPx: CGFloat) -> Sprite? {
        let u = heightPx / 20, m = 3 * u
        let w = Int((15 * u + 2 * m).rounded(.up)), h = Int((20 * u + 2 * m).rounded(.up))
        guard let ctx = context(w, h) else { return nil }
        func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Double) -> CGPath {
            CGPath(roundedRect: CGRect(x: m + x * u, y: m + y * u, width: w * u, height: h * u), cornerWidth: c * u, cornerHeight: c * u, transform: nil)
        }
        let p = CGMutablePath()
        p.addPath(r(4.2, 0, 3.0, 12, 1.5))          // index finger
        p.addPath(r(7.0, 6.2, 2.9, 7.5, 1.45))      // middle
        p.addPath(r(9.6, 7.0, 2.8, 7.0, 1.4))       // ring
        p.addPath(r(12.0, 8.0, 2.6, 6.2, 1.3))      // little finger
        p.addPath(r(4.2, 9.5, 10.4, 9.5, 3.2))      // palm
        let thumb = CGMutablePath()
        thumb.move(to: CGPoint(x: m + 4.6 * u, y: m + 11 * u))
        thumb.addCurve(to: CGPoint(x: m + 1.2 * u, y: m + 10.2 * u), control1: CGPoint(x: m + 3.2 * u, y: m + 9.8 * u), control2: CGPoint(x: m + 2 * u, y: m + 9.4 * u))
        thumb.addCurve(to: CGPoint(x: m + 5 * u, y: m + 16 * u), control1: CGPoint(x: m + 0.2 * u, y: m + 11.2 * u), control2: CGPoint(x: m + 2.6 * u, y: m + 14 * u))
        thumb.closeSubpath()
        p.addPath(thumb)
        // stroke and fill the union: draw the white outline under everything first
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -0.5 * u), blur: 1.6 * u, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        ctx.addPath(p); ctx.setStrokeColor(white); ctx.setLineWidth(2.6 * u); ctx.setLineJoin(.round); ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(p); ctx.setFillColor(white); ctx.fillPath()
        ctx.addPath(p); ctx.setFillColor(black); ctx.fillPath()
        // finger creases
        ctx.setStrokeColor(white); ctx.setLineWidth(0.45 * u); ctx.setLineCap(.round)
        for x in [7.0, 9.6, 12.0] { ctx.move(to: CGPoint(x: m + x * u, y: m + 10.2 * u)); ctx.addLine(to: CGPoint(x: m + x * u, y: m + 13.4 * u)) }
        ctx.strokePath()
        return ctx.makeImage().map { Sprite(image: $0, hot: CGPoint(x: m + 5.7 * u, y: m + 0.4 * u)) }
    }

    static func ibeam(heightPx: CGFloat) -> Sprite? {
        let u = heightPx / 20, m = 3 * u
        let w = Int((8 * u + 2 * m).rounded(.up)), h = Int((20 * u + 2 * m).rounded(.up))
        guard let ctx = context(w, h) else { return nil }
        let cx = m + 4 * u
        let p = CGMutablePath()
        p.move(to: CGPoint(x: m + 0.8 * u, y: m)); p.addQuadCurve(to: CGPoint(x: cx, y: m + 1.6 * u), control: CGPoint(x: cx, y: m))
        p.addQuadCurve(to: CGPoint(x: m + 7.2 * u, y: m), control: CGPoint(x: cx, y: m))
        p.move(to: CGPoint(x: cx, y: m + 1.6 * u)); p.addLine(to: CGPoint(x: cx, y: m + 18.4 * u))
        p.move(to: CGPoint(x: m + 0.8 * u, y: m + 20 * u)); p.addQuadCurve(to: CGPoint(x: cx, y: m + 18.4 * u), control: CGPoint(x: cx, y: m + 20 * u))
        p.addQuadCurve(to: CGPoint(x: m + 7.2 * u, y: m + 20 * u), control: CGPoint(x: cx, y: m + 20 * u))
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addPath(p); ctx.setStrokeColor(white); ctx.setLineWidth(1.6 * u + 2.4 * u); ctx.strokePath()
        ctx.addPath(p); ctx.setStrokeColor(black); ctx.setLineWidth(1.6 * u); ctx.strokePath()
        return ctx.makeImage().map { Sprite(image: $0, hot: CGPoint(x: cx, y: m + 10 * u)) }
    }

    /// A touch-style circle: soft translucent fill with a thin ring; the hotspot is the centre.
    static func dot(heightPx: CGFloat) -> Sprite? {
        let d = heightPx * 0.8, m: CGFloat = 4
        let s = Int((d + 2 * m).rounded(.up))
        guard let ctx = context(s, s) else { return nil }
        let r = CGRect(x: m, y: m, width: d, height: d)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28)); ctx.fillEllipse(in: r)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9)); ctx.setLineWidth(max(1.5, d * 0.06))
        ctx.strokeEllipse(in: r.insetBy(dx: d * 0.03, dy: d * 0.03))
        return ctx.makeImage().map { Sprite(image: $0, hot: CGPoint(x: CGFloat(s) / 2, y: CGFloat(s) / 2)) }
    }
}

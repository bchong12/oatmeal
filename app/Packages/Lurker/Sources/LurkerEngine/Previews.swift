import CoreGraphics
import CoreText
import Foundation
import ImageIO
import LurkerCore
import UniformTypeIdentifiers

/// Stills for checking work without watching: one frame, a strip across a transition, or a labelled contact sheet.
public enum Previews {
    /// Times worth looking at: the start, each region's middle, each clip's start, and an even spread to fill `count`.
    public static func sheetTimes(_ r: Renderer, count: Int = 12) -> [(Double, String)] {
        var out: [(Double, String)] = []
        let d = r.duration
        guard d > 0 else { return [] }
        for z in r.project.regions.zoom {
            if let t = r.map.program(take: z.take, source: (z.start + z.end) / 2).first { out.append((t, "\(z.id) \(String(format: "%.1f", z.depth))×")) }
        }
        let room = max(0, count - out.count)
        for i in 0..<room { out.append((d * (Double(i) + 0.5) / Double(room), "")) }
        return Array(out.sorted { $0.0 < $1.0 }.prefix(count))
    }

    /// A grid of frames with their program times (and what's happening) under each.
    public static func contactSheet(_ r: Renderer, times: [(Double, String)], width: Int = 1536, columns: Int = 4) throws -> CGImage {
        let cols = max(1, min(columns, times.count))
        let rows = Int((Double(times.count) / Double(cols)).rounded(.up))
        let gap = 12, label = 30
        let cellW = (width - gap * (cols + 1)) / cols
        let aspect = r.outputSize.height / r.outputSize.width
        let cellH = Int(Double(cellW) * aspect)
        let height = gap + rows * (cellH + label + gap)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw EngineError("can't draw the sheet") }
        ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        for (i, (t, note)) in times.enumerated() {
            let c = i % cols, row = i / cols
            let x = gap + c * (cellW + gap)
            let yTop = gap + row * (cellH + label + gap)
            let img = try r.image(at: t)
            // CG's origin is bottom-left
            ctx.draw(img, in: CGRect(x: x, y: height - yTop - cellH, width: cellW, height: cellH))
            let text = String(format: "%d:%05.2f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) + (note.isEmpty ? "" : "  " + note)
            draw(text, in: ctx, at: CGPoint(x: x + 2, y: height - yTop - cellH - 21))
        }
        guard let out = ctx.makeImage() else { throw EngineError("can't draw the sheet") }
        return out
    }

    /// Frames evenly spread across a span (a zoom's move, a cut), side by side.
    public static func strip(_ r: Renderer, from a: Double, to b: Double, frames: Int = 6, width: Int = 1536) throws -> CGImage {
        let n = max(2, frames)
        let times = (0..<n).map { (a + (b - a) * Double($0) / Double(n - 1), "") }
        return try contactSheet(r, times: times, width: width, columns: n)
    }

    static func draw(_ s: String, in ctx: CGContext, at p: CGPoint) {
        let font = CTFontCreateWithName("Menlo" as CFString, 15, nil)
        let attrs: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font,
                                                    .init(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 0.85, green: 0.86, blue: 0.9, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        ctx.textPosition = p
        CTLineDraw(line, ctx)
    }

    /// Writes JPEG (smaller, for agents) or PNG by extension.
    public static func write(_ img: CGImage, to url: URL, quality: Double = 0.85) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let type = url.pathExtension.lowercased() == "png" ? UTType.png : UTType.jpeg
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { throw EngineError("can't write \(url.path)") }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw EngineError("can't write \(url.path)") }
    }
}

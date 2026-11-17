import AppKit
import CoreGraphics
import LurkerCore

/// Canvas backgrounds, drawn once per render at the size needed.
/// Vocabulary (canvas.background): {type: aurora | aura | photo | gradient | color | image | wallpaper | none, name?, colors?, color?,
/// path?, blur?}
public enum Backgrounds {
    public static let auroraNames = Array(auroras.keys).sorted()
    public static let auraNames = Array(auras.keys).sorted()

    /// The bundled photos (Resources/Backgrounds, credited in CREDITS.md there): name, photographer, Unsplash photo id.
    public static let photos: [(name: String, by: String, unsplash: String)] = [
        ("gradients/violet", "MagicPattern", "8h_tctpq4h0"),
        ("gradients/ember", "Antonius Harel", "WsaPcg512jE"),
        ("gradients/horizon", "César Couto", "27HiryxnHJk"),
        ("gradients/pastel", "MagicPattern", "oPH_5xuMgQw"),
        ("shapes/flow", "Milad Fakurian", "E8Ufcyxz514"),
        ("shapes/silk", "Richard Horvath", "_nWaeTF6qo0"),
        ("shapes/teal", "Pawel Czerwinski", "ERcQ81KaX9g"),
        ("shapes/ribbon", "Pawel Czerwinski", "FAlYVtV1kRg"),
        ("mountains/ridges", "Sven Pieren", "ibikgDapcp4"),
        ("mountains/layers", "Pinal Jain", "x-XwnC7FgFM"),
        ("mountains/blue", "Alessio Soggetti", "PdGBci-4jR8"),
        ("mountains/fog", "Alessio Soggetti", "gdE-5Oui1Y0"),
        ("water/calm", "Mathyas Kurmann", "jnHQsTfq2Og"),
        ("water/turquoise", "Albert Stoynov", "iYyIbZx92zY"),
        ("water/ripples", "Meina Yin", "gDjCMip9gu8"),
        ("water/surf", "Andrzej Kryszpiniuk", "4wFqHZ1ONnM"),
        ("dunes/amber", "Wolfgang Hasselmann", "pVr6wvUneMk"),
        ("dunes/white", "Royce Fonseca", "48bRZya67Po"),
        ("dunes/crest", "Mike Iukhtenko", "zuueig1w8WI"),
        ("dunes/gold", "Zetong Li", "HEf0fKgJA1Q"),
        ("night/stars", "Kai Pilger", "Ef6iL87-vOA"),
        ("night/milkyway", "Felix Mittermeier", "Knwea-mLGAg"),
        ("night/pines", "Jeremy Thomas", "pq2DJBntZW0"),
        ("night/deep", "Shakti Rajpurohit", "ggs-47SjYy0"),
    ]

    public static let photoNames = photos.map(\.name)
    /// Photo packs in display order: gradients, shapes, mountains, water, dunes, night.
    public static let photoPacks: [String] = photos.reduce(into: []) { packs, p in
        let pack = String(p.name.split(separator: "/")[0])
        if !packs.contains(pack) { packs.append(pack) }
    }

    /// Where the bundled photos are: inside the app, or in the repository for tests and debug builds.
    public static let photoDirectory: URL? = {
        let fm = FileManager.default
        if let r = Bundle.main.resourceURL?.appending(path: "Backgrounds"), fm.fileExists(atPath: r.path) { return r }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Backgrounds")
        return fm.fileExists(atPath: repo.path) ? repo : nil
    }()

    /// Checks a canvas.background value without drawing it, so a bad one is refused when it's set rather than at render.
    public static func validate(_ spec: JSONValue) throws {
        if case .null = spec { return }
        guard case .object = spec else { throw EngineError("canvas.background is an object like {type: \"photo\", name: \"dunes/crest\"}") }
        func str(_ k: String) -> String? { if case .string(let s)? = spec.value(at: [k]) { s } else { nil } }
        switch str("type") ?? "aurora" {
        case "aurora":
            if let n = str("name"), auroras[n] == nil { throw EngineError("aurora must be one of \(auroraNames.joined(separator: ", "))") }
        case "aura":
            if let n = str("name"), auras[n] == nil { throw EngineError("aura must be one of \(auraNames.joined(separator: ", "))") }
        case "photo":
            if let n = str("name"), !photoNames.contains(n) { throw EngineError("photo must be one of \(photoNames.joined(separator: ", "))") }
        case "image":
            guard let p = str("path"), FileManager.default.fileExists(atPath: (p as NSString).expandingTildeInPath) else {
                throw EngineError("an image background needs path, an image file that exists")
            }
        case "gradient", "color", "wallpaper", "none": break
        case let t: throw EngineError("background type \(t) isn't one of aurora, aura, photo, gradient, color, image, wallpaper, none")
        }
    }

    public static func photoURL(_ name: String) -> URL? {
        guard photoNames.contains(name) else { return nil }
        return photoDirectory?.appending(path: name.replacingOccurrences(of: "/", with: "-") + ".heic")
    }

    public static func image(_ spec: JSONValue, size: CGSize) throws -> CGImage {
        let type = spec.value(at: ["type"]).flatMap { if case .string(let s) = $0 { s } else { nil } } ?? "aurora"
        func str(_ k: String) -> String? { if case .string(let s)? = spec.value(at: [k]) { s } else { nil } }
        let w = max(2, Int(size.width)), h = max(2, Int(size.height))
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw EngineError("can't draw the background") }
        switch type {
        case "none":
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        case "color":
            ctx.setFillColor(color(str("color") ?? "#1C1C1E")); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        case "gradient":
            var stops: [String] = []
            if case .array(let a)? = spec.value(at: ["colors"]) { stops = a.compactMap { if case .string(let s) = $0 { s } else { nil } } }
            if stops.isEmpty { stops = ["#C3F5FB", "#5590E0"] }
            if stops.count == 1 { stops.append(stops[0]) }
            let grad = CGGradient(colorsSpace: cs, colors: stops.map(color) as CFArray, locations: (0..<stops.count).map { CGFloat($0) / CGFloat(stops.count - 1) })!
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case "photo":
            let name = str("name") ?? "gradients/violet"
            guard photoNames.contains(name) else { throw EngineError("photo must be one of \(photoNames.joined(separator: ", "))") }
            guard let url = photoURL(name), FileManager.default.fileExists(atPath: url.path) else {
                throw EngineError("the bundled background photos aren't installed (Resources/Backgrounds)")
            }
            try cover(ctx, w, h, url)
        case "image", "wallpaper":
            let url: URL?
            if type == "wallpaper" { url = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) } }
            else { url = str("path").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } }
            guard let url else { throw EngineError("can't read background image \(str("path") ?? "")") }
            try cover(ctx, w, h, url)
        case "aura":
            let name = str("name") ?? "sky"
            guard let (base, blobs) = auras[name] else { throw EngineError("aura must be one of \(auraNames.joined(separator: ", "))") }
            drawAura(ctx, w, h, base, blobs)
        default:
            let name = str("name") ?? "aqua"
            guard let (base, bands) = auroras[name] else { throw EngineError("aurora must be one of \(auroraNames.joined(separator: ", "))") }
            drawAurora(ctx, w, h, base, bands)
        }
        guard var out = ctx.makeImage() else { throw EngineError("can't draw the background") }
        if case .number(let blur)? = spec.value(at: ["blur"]), blur > 0 { out = blurred(out, sigma: blur * Double(h) / 1080) ?? out }
        // soft procedural fields get blurred and grained so big gradients don't band in 8-bit video
        if type == "aurora" || type == "aura" { out = blurred(out, sigma: (type == "aura" ? 0.06 : 0.035) * Double(h)) ?? out }
        return out
    }

    /// Draws an image file to fill the canvas, cropping the overflow. It's decoded at the size it's drawn, so a small
    /// swatch of a 4K photo stays cheap.
    static func cover(_ ctx: CGContext, _ w: Int, _ h: Int, _ url: URL) throws {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let iw = props[kCGImagePropertyPixelWidth] as? Int, let ih = props[kCGImagePropertyPixelHeight] as? Int, iw > 0, ih > 0 else {
            throw EngineError("can't read background image \(url.path)")
        }
        let s = max(Double(w) / Double(iw), Double(h) / Double(ih))
        let longSide = min(max(iw, ih), Int((Double(max(iw, ih)) * s).rounded(.up)) + 2)
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: longSide]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw EngineError("can't read background image \(url.path)") }
        let k = max(Double(w) / Double(img.width), Double(h) / Double(img.height))
        let dw = Double(img.width) * k, dh = Double(img.height) * k
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: (Double(w) - dw) / 2, y: (Double(h) - dh) / 2, width: dw, height: dh))
    }

    static func color(_ hex: String) -> CGColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) }
        return CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    static func blurred(_ img: CGImage, sigma: Double) -> CGImage? {
        let ci = CIImage(cgImage: img).clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!]).createCGImage(ci, from: ci.extent)
    }

    /// Round soft colour blobs on a light base: (base, [(colour, x, y, radius as share of the long side)]).
    static let auras: [String: (String, [(String, Double, Double, Double)])] = [
        "sky": ("#A9DCF9", [("#C3F5FB", 0.12, 0.10, 0.55), ("#CAF3FA", 0.92, 0.08, 0.45), ("#A2D6FC", 0.50, 0.45, 0.50), ("#5590E0", 0.45, 1.05, 0.55), ("#87B0EB", 0.95, 0.95, 0.40)]),
        "mint": ("#D6F7EA", [("#ECFFF7", 0.15, 0.10, 0.55), ("#BDEFE0", 0.90, 0.15, 0.45), ("#7FD3B8", 0.40, 1.05, 0.55), ("#A9E3F2", 0.95, 0.90, 0.40)]),
        "peach": ("#FFE6D8", [("#FFF4EC", 0.15, 0.10, 0.55), ("#FFD3C2", 0.88, 0.12, 0.45), ("#F59B82", 0.45, 1.05, 0.55), ("#FFC4D6", 0.95, 0.90, 0.40)]),
        "lavender": ("#E7E1FF", [("#F6F3FF", 0.15, 0.10, 0.55), ("#D6CCFF", 0.90, 0.12, 0.45), ("#8E7BEF", 0.45, 1.05, 0.55), ("#C7DDFF", 0.95, 0.92, 0.40)]),
        "sand": ("#F3EBDD", [("#FBF6EE", 0.15, 0.10, 0.55), ("#EADBC2", 0.90, 0.15, 0.45), ("#C9A97C", 0.45, 1.05, 0.55), ("#E8D6C9", 0.95, 0.90, 0.40)]),
        "mist": ("#ECEEF1", [("#FAFBFC", 0.15, 0.10, 0.55), ("#E0E4EA", 0.90, 0.12, 0.45), ("#AEB6C2", 0.45, 1.05, 0.55), ("#D5DCE6", 0.95, 0.90, 0.40)]),
        "dusk": ("#1D2442", [("#2E3A6B", 0.15, 0.10, 0.55), ("#4B3F8F", 0.90, 0.15, 0.45), ("#0E1226", 0.45, 1.05, 0.55), ("#3F5FA8", 0.95, 0.90, 0.40)]),
        "graphite": ("#24272D", [("#353A43", 0.15, 0.10, 0.55), ("#2C3038", 0.90, 0.15, 0.45), ("#15171B", 0.45, 1.05, 0.55), ("#3D4350", 0.95, 0.90, 0.40)]),
    ]

    static func drawAura(_ ctx: CGContext, _ w: Int, _ h: Int, _ base: String, _ blobs: [(String, Double, Double, Double)]) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let long = Double(max(w, h))
        ctx.setFillColor(color(base)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for (hex, x, y, r) in blobs {
            let c = color(hex)
            let g = CGGradient(colorsSpace: cs, colors: [c, c.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
            let p = CGPoint(x: x * Double(w), y: (1 - y) * Double(h))
            ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r * long, options: [])
        }
    }

    /// Diagonal light streaks over deeper corners: (base, [(colour, x, y, length, thickness, angle°, opacity)]).
    static let auroras: [String: (String, [(String, Double, Double, Double, Double, Double, Double)])] = {
        func set(_ base: String, _ deep: [String], _ light: [String], lightAlpha: [Double] = [0.95, 0.85, 0.8, 0.7], topAlpha: Double = 0.8) -> (String, [(String, Double, Double, Double, Double, Double, Double)]) {
            (base, [(deep[0], 0.55, 1.08, 0.62, 0.30, -4, 1.0), (deep[1], 1.02, 0.02, 0.42, 0.60, -30, 0.9), (deep[2], -0.02, 1.0, 0.36, 0.60, 30, 0.8),
                    (deep[3], 1.02, 1.0, 0.40, 0.55, -25, 0.9), (deep[4], 0.48, 0.0, 0.50, 0.28, 8, topAlpha),
                    (light[0], 0.24, 0.20, 0.62, 0.16, 32, lightAlpha[0]), (light[1], 0.62, 0.52, 0.72, 0.13, 32, lightAlpha[1]),
                    (light[2], 0.08, 0.66, 0.50, 0.18, 32, lightAlpha[2]), (light[3], 0.86, 0.38, 0.45, 0.12, 32, lightAlpha[3])])
        }
        return [
            "aqua": set("#ABE5F8", ["#5E95E2", "#78A9EA", "#86B4EE", "#8DBDF0", "#97CDF9"], ["#EAFCFF", "#D4F7FD", "#C8F3FB", "#E2FAFE"]),
            "violet": set("#D9D2FB", ["#7C68E8", "#9A86EF", "#A493F0", "#B6A6F5", "#C1B3F8"], ["#F6F3FF", "#EAE4FF", "#E4DCFF", "#F1EDFF"]),
            "mint": set("#C9F2E4", ["#3FAE9A", "#5FC3B3", "#6BC9C4", "#86D6C8", "#9EE0D2"], ["#F0FFF9", "#DDFBF0", "#D2F8EC", "#E8FDF6"]),
            "sunset": set("#FFDCCB", ["#E8708A", "#F08C6E", "#F29A9A", "#F5A88A", "#F9BFA4"], ["#FFF6EE", "#FFE9DD", "#FFE2D6", "#FFF0E8"]),
            "night": set("#1A2348", ["#0A0F26", "#0E1530", "#101836", "#0C1330", "#263778"], ["#3E6BD0", "#5A4FC8", "#2E8FC0", "#4C7FE0"],
                         lightAlpha: [0.55, 0.5, 0.45, 0.4], topAlpha: 0.7),
            "mono": set("#E9EBEE", ["#A9AFB8", "#BCC1C8", "#C4C8CE", "#C9CDD3", "#D3D6DB"], ["#FFFFFF", "#F6F7F8", "#F2F3F5", "#FAFAFB"]),
        ]
    }()

    static func drawAurora(_ ctx: CGContext, _ w: Int, _ h: Int, _ base: String, _ bands: [(String, Double, Double, Double, Double, Double, Double)]) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let long = Double(max(w, h))
        ctx.setFillColor(color(base)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for (hex, x, y, len, thick, deg, a) in bands {
            let c = color(hex)
            let g = CGGradient(colorsSpace: cs, colors: [c.copy(alpha: a)!, c.copy(alpha: a * 0.45)!, c.copy(alpha: 0)!] as CFArray, locations: [0, 0.45, 1])!
            ctx.saveGState()
            ctx.translateBy(x: x * Double(w), y: (1 - y) * Double(h))
            ctx.rotate(by: deg * .pi / 180)
            ctx.scaleBy(x: 1, y: max(0.05, thick))
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: len * long, options: [])
            ctx.restoreGState()
        }
    }
}

public struct EngineError: LocalizedError, CustomStringConvertible, Sendable {
    public let description: String
    public var errorDescription: String? { description }
    public init(_ d: String) { description = d }
}

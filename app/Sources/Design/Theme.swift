import SwiftUI
import AppKit

/// Colours and type from the Oatmeal designs in Purist ("Oatmeal" file, "landing (fun)").
/// Ink on oat cream, honey for the one warm accent, espresso for dark moments, red for live states.
enum DF {
    static let ink = Color(hex: 0x1C1915)
    static let muted = Color(hex: 0x6E665A)
    static let faint = Color(hex: 0x9C9488)
    static let line = Color(hex: 0x1C1915, alpha: 0.10)
    static let wash = Color(hex: 0xEFE7CF)
    static let canvas = Color(hex: 0xFCF8EA)
    static let paper = Color(hex: 0xFFFDF8)
    static let now = Color(hex: 0xE5555F)
    static let checkbox = Color(hex: 0xC9C1AE)

    // Brand.
    static let honey = Color(hex: 0xF6D27C)
    static let honeyDeep = Color(hex: 0xD99A2B)
    static let espresso = Color(hex: 0x3B2A20)
    static let umber = Color(hex: 0x4A3426)
    static let oat = Color(hex: 0xE8DCC4)

    // Labels.
    static let work = Color(hex: 0x7B66A8)
    static let tasks = Color(hex: 0x3F7A55)
    static let personal = Color(hex: 0xB0822F)

    // States.
    static let thrivingBg = Color(hex: 0xE5F1E8), thrivingInk = Color(hex: 0x2E7D55)
    static let okayBg = Color(hex: 0xFCF1D9), okayInk = Color(hex: 0x826322)
    static let tiredBg = Color(hex: 0xFDECEC), tiredInk = Color(hex: 0xB3363F)

    static func label(_ name: String) -> Color {
        switch name.lowercased() {
        case "work": return work
        case "tasks": return tasks
        default: return personal
        }
    }

    /// Everything reads a notch smaller than the Purist mockups, which were drawn at 2x presence.
    static let scale: CGFloat = 0.86
    /// Body and UI text: Figtree.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Figtree", size: (size * scale).rounded()).weight(weight)
    }
    /// Headings: Young Serif (one weight).
    static func serif(_ size: CGFloat) -> Font {
        .custom("Young Serif", size: (size * scale).rounded())
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Small pill used for durations, totals and counts.
struct DurationPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DF.font(12, .semibold))
            .foregroundStyle(DF.muted)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(DF.wash, in: Capsule())
    }
}

struct CardStyle: ViewModifier {
    var selected = false
    func body(content: Content) -> some View {
        content
            .background(DF.paper, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? DF.ink : DF.line, lineWidth: selected ? 1.5 : 1))
            .shadow(color: selected ? DF.ink.opacity(0.08) : .clear, radius: 7, y: 4)
    }
}

extension View {
    func dfCard(selected: Bool = false) -> some View { modifier(CardStyle(selected: selected)) }
}

/// The Oatmeal app icon: the wave-loop on an umber tile.
struct BrandMark: View {
    var size: CGFloat = 22
    var body: some View {
        if let img = BrandAssets.mark {
            Image(nsImage: img).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
        }
    }
}

/// One-colour mark for dark surfaces like the pill.
struct BrandMarkMono: View {
    var size: CGFloat = 16
    var color: Color = .white
    var body: some View {
        if let img = BrandAssets.template {
            Image(nsImage: img).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                .foregroundStyle(color).frame(width: size, height: size)
        }
    }
}

enum BrandAssets {
    static let template: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MarkTemplate", withExtension: "png", subdirectory: "Brand"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        return img
    }()
    static let mark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "mark", withExtension: "png", subdirectory: "Brand") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

func formatMinutes(_ m: Int) -> String {
    if m < 60 { return "\(m)m" }
    let h = m / 60, r = m % 60
    return r == 0 ? "\(h)h" : "\(h)h \(r)m"
}

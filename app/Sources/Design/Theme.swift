import SwiftUI
import AppKit

/// Colours and type from the Oatmeal designs in Purist ("Oatmeal" file, the "Capture" frames).
/// Notion's look: ink on white, warm greys for the sidebar and wells, honey only as a highlight,
/// red for live states.
enum DF {
    static let ink = Color(hex: 0x191919)
    static let muted = Color(hex: 0x787774)
    static let faint = Color(hex: 0x9B9A97)
    static let line = Color(hex: 0x000000, alpha: 0.09)
    static let wash = Color(hex: 0xF1F1EF)
    static let canvas = Color(hex: 0xF7F7F5)
    static let paper = Color(hex: 0xFFFFFF)
    static let now = Color(hex: 0xEB5757)
    static let checkbox = Color(hex: 0xD3D1CB)

    // Brand.
    static let honey = Color(hex: 0xF9DE95)
    static let honeyDeep = Color(hex: 0xF2B43A)
    static let espresso = Color(hex: 0x191919)
    static let umber = Color(hex: 0x37352F)
    static let oat = Color(hex: 0xE9E9E7)

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

    // Page layout, shared by every screen so edges line up.
    /// Side margin of list screens (Recent, Meetings, Flow): headers, rows and their dividers all start here.
    static let inset: CGFloat = 28
    /// Document screens (a meeting, Settings): a centred column this wide, with `docInset` inside it.
    static let docWidth: CGFloat = 800
    static let docInset: CGFloat = 40
    /// Space above the page title on every screen.
    static let pageTop: CGFloat = 26

    /// Everything reads a notch smaller than the Purist mockups, which were drawn at 2x presence.
    static let scale: CGFloat = 0.86
    /// Body and UI text: Inter.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: (size * scale).rounded()).weight(weight)
    }
    /// Headings: Inter semibold, like Notion's page titles. (Still called serif so the call sites
    /// read the same; it was Young Serif before.)
    static func serif(_ size: CGFloat) -> Font {
        .custom("Inter", size: (size * scale).rounded()).weight(.semibold)
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

/// A group of settings rows, Notion style: no box, just a hairline above and below.
struct CardStyle: ViewModifier {
    var selected = false
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) { Rectangle().fill(DF.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(DF.line).frame(height: 1) }
    }
}

extension View {
    func dfCard(selected: Bool = false) -> some View { modifier(CardStyle(selected: selected)) }
}

/// Oatmeal's face (drawn from Notion Avatar parts) on a soft honey tile, the way Notion shows a
/// page icon.
struct BrandMark: View {
    var size: CGFloat = 22
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(Color(hex: 0xFCEBC2))
            .overlay(alignment: .bottom) {
                if let img = BrandAssets.face {
                    Image(nsImage: img).resizable().interpolation(.high).scaledToFit()
                        .frame(width: size * 1.12, height: size * 1.12).offset(y: size * 0.06)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .frame(width: size, height: size)
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
    static let face: NSImage? = {
        guard let url = Bundle.main.url(forResource: "face", withExtension: "png", subdirectory: "Brand") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

func formatMinutes(_ m: Int) -> String {
    if m < 60 { return "\(m)m" }
    let h = m / 60, r = m % 60
    return r == 0 ? "\(h)h" : "\(h)h \(r)m"
}

import SwiftUI
import AppKit

/// Notion-style page pieces shared by Flow, Meetings, a meeting and Settings (the "Flow", "Notes",
/// "Meeting" and "Settings" frames in the Oatmeal Purist file): an icon above a big title, a line
/// of description, then content straight on the page with hairlines, no cards.
extension DF {
    /// Reading column of Flow, a meeting and Settings.
    static let pageWidth: CGFloat = 820
    /// The Meetings table is wider.
    static let tableWidth: CGFloat = 940
    /// Side padding inside a page column.
    static let pagePad: CGFloat = 48
}

extension View {
    /// Centres content in a page column `width` wide with the page's side padding.
    func pageColumn(_ width: CGFloat = DF.pageWidth) -> some View {
        padding(.horizontal, DF.pagePad)
            .frame(maxWidth: width, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

/// A page's icon: one of Oatmeal's faces on a honey tile, or a symbol on a grey one.
struct PageIcon: View {
    enum Art { case face(String), symbol(String), meeting }
    let art: Art
    var size: CGFloat = 56

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(isFace ? Color(hex: 0xFCEBC2) : DF.wash)
            .overlay(alignment: isFace ? .bottom : .center) {
                switch art {
                case .face(let name):
                    if let img = Self.image(name) {
                        Image(nsImage: img).resizable().interpolation(.high).scaledToFit()
                            .frame(width: size * 1.05, height: size * 1.05).offset(y: size * 0.08)
                    }
                case .symbol(let s):
                    Image(systemName: s).font(.system(size: size * 0.4, weight: .regular)).foregroundStyle(DF.muted)
                case .meeting:
                    MeetingGlyph(size: size * 0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .frame(width: size, height: size)
    }

    private var isFace: Bool { if case .face = art { return true }; return false }

    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage? {
        if let c = cache[name] { return c }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Brand"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[name] = img
        return img
    }
}

/// Icon, title and a line of description, with actions to the right of the title.
struct NotionHeader<Actions: View, Below: View>: View {
    let icon: PageIcon.Art
    let title: String
    var description: String = ""
    @ViewBuilder var actions: Actions
    @ViewBuilder var below: Below

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageIcon(art: icon).padding(.bottom, 14)
            HStack(alignment: .center, spacing: 10) {
                Text(title).font(DF.font(40, .bold)).tracking(-0.8).lineLimit(1)
                Spacer(minLength: 12)
                actions.fixedSize()
            }
            if !description.isEmpty {
                Text(description).font(DF.font(16)).foregroundStyle(DF.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            below
        }
    }
}

extension NotionHeader where Below == EmptyView {
    init(icon: PageIcon.Art, title: String, description: String = "", @ViewBuilder actions: () -> Actions) {
        self.init(icon: icon, title: title, description: description, actions: actions, below: { EmptyView() })
    }
}

/// Notion's database views: plain words, the open one on a soft grey.
struct ViewTabs<T: Hashable>: View {
    let items: [(T, String, String)]   // value, title, SF symbol
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let (value, title, symbol) = items[i]
                ViewTab(title: title, symbol: symbol, on: selection == value) {
                    withAnimation(.snappy(duration: 0.18)) { selection = value }
                }
            }
        }
    }
}

private struct ViewTab: View {
    let title: String
    let symbol: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11.5, weight: .medium))
                Text(title).font(DF.font(15, .medium))
            }
            .foregroundStyle(on ? DF.ink : DF.muted)
            .padding(.horizontal, 9).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.black.opacity(0.05) : hover ? Color.black.opacity(0.03) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// A Notion select tag.
struct NotionTag: View {
    enum Tone { case grey, yellow, green, red }
    let text: String
    var tone: Tone = .grey
    var spinner = false
    var body: some View {
        let (bg, fg): (Color, Color) = {
            switch tone {
            case .grey: (Color(hex: 0xF1F1EF), Color(hex: 0x787774))
            case .yellow: (Color(hex: 0xFDECC8), Color(hex: 0x402C1B))
            case .green: (Color(hex: 0xDBEDDB), Color(hex: 0x1C3829))
            case .red: (Color(hex: 0xFFE2DD), Color(hex: 0x5D1715))
            }
        }()
        HStack(spacing: 5) {
            if spinner { DFSpinner(size: 9, color: fg) }
            Text(text).font(DF.font(13, .medium)).lineLimit(1)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 7).frame(height: 21)
        .background(bg, in: RoundedRectangle(cornerRadius: 4))
        .fixedSize()
    }
}

/// A person's initials on a soft circle; a few overlap in a row.
struct InitialsStack: View {
    let names: [String]
    var size: CGFloat = 22
    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(names.prefix(3).enumerated()), id: \.offset) { i, n in
                Text(Self.initials(n)).font(.custom("Inter", size: size * 0.42).weight(.semibold))
                    .foregroundStyle(DF.umber)
                    .frame(width: size, height: size)
                    .background(Self.tint(n), in: Circle())
                    .overlay(Circle().strokeBorder(DF.paper, lineWidth: 1.5))
                    .zIndex(Double(3 - i))
            }
            if names.count > 3 {
                Text("+\(names.count - 3)").font(DF.font(12, .medium)).foregroundStyle(DF.muted).padding(.leading, 10)
            }
        }
    }
    static func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" }).prefix(2)
        let s = parts.compactMap(\.first).map(String.init).joined().uppercased()
        return s.isEmpty ? "?" : s
    }
    static func tint(_ name: String) -> Color {
        let tints: [UInt32] = [0xFDECC8, 0xDBEDDB, 0xD3E5EF, 0xE8DEEE, 0xFADEC9, 0xF5E0E9]
        let h = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hex: tints[h % tints.count])
    }
}

/// A full-width hairline.
struct Hairline: View {
    var body: some View { Rectangle().fill(DF.line).frame(height: 1) }
}

/// A small grey chip, like the speech model under Flow's title.
struct InfoChip: View {
    let text: String
    var dot: Color? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            Text(text).font(DF.font(13, .medium)).foregroundStyle(DF.muted)
        }
        .padding(.horizontal, 8).frame(height: 24)
        .background(DF.wash, in: RoundedRectangle(cornerRadius: 6))
        .fixedSize()
    }
}

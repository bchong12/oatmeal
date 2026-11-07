import SwiftUI
import AppKit

// Oatmeal's own controls. Nothing here uses AppKit's buttons, switches, pickers, menus or alerts:
// menus and dialogs draw in `PopupLayer`, which sits over the whole window.

// MARK: - Buttons

enum DFButtonKind { case primary, secondary, ghost, honey, danger }

/// `.buttonStyle(.df(.primary))`: ink, outlined paper, quiet ghost, the honey call to action, or red.
struct DFButtonStyle: ButtonStyle {
    var kind: DFButtonKind = .secondary
    var height: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, kind: kind, height: height)
    }

    private struct Face: View {
        let configuration: Configuration
        let kind: DFButtonKind
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            configuration.label
                .labelStyle(DFLabelStyle())
                .font(DF.font(13, .semibold))
                .foregroundStyle(fg)
                .padding(.horizontal, kind == .ghost ? 9 : 12).frame(height: height)
                .background(bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: kind == .honey ? 1.5 : 1))
                .opacity(enabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Rectangle())
                .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h && enabled } }
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }

        private var fg: Color {
            switch kind {
            case .primary: .white
            case .danger: DF.tiredInk
            case .ghost: hover ? DF.ink : DF.muted
            default: DF.ink
            }
        }
        private var bg: Color {
            switch kind {
            case .primary: hover ? Color(hex: 0x3A342C) : DF.ink
            case .secondary: hover ? Color(hex: 0xF7F1E1) : DF.paper
            case .ghost: hover ? DF.wash.opacity(0.75) : .clear
            case .honey: hover ? Color(hex: 0xF9DC93) : DF.honey
            case .danger: hover ? DF.tiredBg : DF.paper
            }
        }
        private var border: Color {
            switch kind {
            case .secondary: DF.line.opacity(1.6)
            case .danger: DF.tiredInk.opacity(0.25)
            case .honey: DF.ink
            default: .clear
            }
        }
    }
}

/// Icon then title, a little tighter than the system's.
struct DFLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 11.5, weight: .semibold))
            configuration.title
        }
    }
}

/// Square icon button: muted glyph, wash on hover, ink while `active`.
struct DFIconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, size: size, active: active)
    }

    private struct Face: View {
        let configuration: Configuration
        let size: CGFloat
        let active: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active || hover ? DF.ink : DF.muted)
                .frame(width: size, height: size)
                .background(active || hover ? DF.wash.opacity(0.85) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .opacity(enabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .contentShape(Rectangle())
                .onHover { hover = $0 && enabled }
        }
    }
}

extension ButtonStyle where Self == DFButtonStyle {
    static func df(_ kind: DFButtonKind = .secondary, height: CGFloat = 30) -> DFButtonStyle { DFButtonStyle(kind: kind, height: height) }
}

extension ButtonStyle where Self == DFIconButtonStyle {
    static func dfIcon(size: CGFloat = 28, active: Bool = false) -> DFIconButtonStyle { DFIconButtonStyle(size: size, active: active) }
}

// MARK: - Switch

/// `.toggleStyle(.df)`: a small ink switch with a white knob.
struct DFSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }

    private struct Face: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            let on = configuration.isOn
            HStack(spacing: 10) {
                configuration.label
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? DF.ink : Color(hex: 0xDCD3BE))
                    Circle().fill(.white).frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .padding(2)
                }
                .frame(width: 34, height: 20)
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onTapGesture {
                    guard enabled else { return }
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { configuration.isOn.toggle() }
                }
            }
        }
    }
}

extension ToggleStyle where Self == DFSwitchStyle {
    static var df: DFSwitchStyle { DFSwitchStyle() }
}

/// Round radio for single-choice rows.
struct DFRadio: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? DF.ink : Color(hex: 0xCFC6B2), lineWidth: 1.5)
            if on { Circle().fill(DF.ink).padding(4.5).transition(.scale) }
        }
        .frame(width: 18, height: 18)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: on)
    }
}

/// Square check for multi-select rows.
struct DFCheck: View {
    let on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 4.5)
            .fill(on ? DF.ink : DF.paper)
            .overlay(RoundedRectangle(cornerRadius: 4.5).strokeBorder(on ? DF.ink : Color(hex: 0xCFC6B2), lineWidth: 1.5))
            .overlay { if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) } }
            .frame(width: 16, height: 16)
    }
}

// MARK: - Tabs

/// Underlined text tabs: "Notes   My notes   Transcript".
struct DFTabs<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var spacing: CGFloat = 20
    @Namespace private var ns

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(items.indices, id: \.self) { i in
                let (value, title) = items[i]
                let on = selection == value
                Button { withAnimation(.snappy(duration: 0.22)) { selection = value } } label: {
                    VStack(spacing: 8) {
                        Text(title).font(DF.font(14, on ? .semibold : .medium)).foregroundStyle(on ? DF.ink : DF.muted)
                        ZStack {
                            if on { Capsule().fill(DF.ink).frame(height: 2).matchedGeometryEffect(id: "underline", in: ns) }
                            else { Color.clear.frame(height: 2) }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Pill-shaped segmented switch, for small either/or choices.
struct DFSegmented<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let (value, title) = items[i]
                let on = selection == value
                Button { withAnimation(.snappy(duration: 0.22)) { selection = value } } label: {
                    Text(title).font(DF.font(12, on ? .semibold : .medium)).foregroundStyle(on ? DF.ink : DF.muted)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 6).fill(DF.paper)
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(DF.wash.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Dropdown

/// A select box that opens Oatmeal's own menu.
struct DFSelect<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var width: CGFloat = 240
    @State private var frame: CGRect = .zero
    @State private var hover = false

    var body: some View {
        let current = options.first { $0.0 == selection }?.1 ?? ""
        Button {
            Popups.shared.showMenu(options.map { o in .action(o.1, checked: o.0 == selection) { selection = o.0 } }, below: frame, width: width)
        } label: {
            HStack(spacing: 8) {
                Text(current).font(DF.font(13, .medium)).foregroundStyle(DF.ink).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(DF.faint)
            }
            .padding(.horizontal, 10).frame(width: width, height: 30)
            .background(hover ? Color(hex: 0xF7F1E1) : DF.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DF.line.opacity(1.6)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .popupAnchor($frame)
    }
}

// MARK: - Progress

struct DFProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(DF.wash)
                Capsule().fill(DF.ink).frame(width: max(4, g.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.25), value: value)
    }
}

/// A turning arc, for work with no percentage.
struct DFSpinner: View {
    var size: CGFloat = 14
    var color: Color = DF.ink
    @State private var turn = false
    var body: some View {
        Circle().trim(from: 0, to: 0.72)
            .stroke(color, style: StrokeStyle(lineWidth: max(1.5, size / 8), lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turn ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: turn)
            .onAppear { turn = true }
    }
}

// MARK: - Fields

/// Plain text field on a soft well.
struct DFTextField: View {
    let prompt: String
    @Binding var text: String
    var height: CGFloat = 32
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain).font(DF.font(14))
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 10).frame(height: height)
            .background(DF.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? DF.ink.opacity(0.55) : DF.line.opacity(1.6), lineWidth: focused ? 1.5 : 1))
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

// MARK: - Menus and dialogs

/// One row of an Oatmeal menu.
struct DFMenuItem {
    enum Kind { case action, submenu, header, divider }
    var kind: Kind
    var title = ""
    var icon: String?
    var checked = false
    var destructive = false
    var hint: String?
    var children: [DFMenuItem] = []
    var perform: () -> Void = {}

    static func action(_ title: String, icon: String? = nil, checked: Bool = false, destructive: Bool = false, hint: String? = nil,
                       _ perform: @escaping () -> Void) -> DFMenuItem {
        DFMenuItem(kind: .action, title: title, icon: icon, checked: checked, destructive: destructive, hint: hint, perform: perform)
    }
    static func submenu(_ title: String, icon: String? = nil, _ children: [DFMenuItem]) -> DFMenuItem {
        DFMenuItem(kind: .submenu, title: title, icon: icon, children: children)
    }
    static func header(_ title: String) -> DFMenuItem { DFMenuItem(kind: .header, title: title) }
    static let divider = DFMenuItem(kind: .divider)
}

/// A confirm or name prompt, drawn over the window.
struct DFDialog {
    var title: String
    var message: String = ""
    /// Shows a text field starting with this text; nil for a plain confirm.
    var field: String?
    var placeholder = ""
    var confirm: String
    var destructive = false
    var onConfirm: (String) -> Void
}

/// The open menu or dialog. `PopupLayer` draws them; anything can open one.
@MainActor
final class Popups: ObservableObject {
    static let shared = Popups()
    /// The window-wide coordinate space anchors are measured in.
    static let space = "oatmeal-root"

    struct Menu {
        var items: [DFMenuItem]
        var anchor: CGRect
        var width: CGFloat
        var id = UUID()
    }

    @Published private(set) var menu: Menu?
    @Published private(set) var dialog: DFDialog?
    private var monitor: Any?

    /// Opens under (or, near the bottom, over) a control's frame.
    func showMenu(_ items: [DFMenuItem], below anchor: CGRect, width: CGFloat = 220) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) { menu = Menu(items: items, anchor: anchor, width: width) }
        watchEscape()
    }

    /// Opens at the pointer, for right-clicks.
    func showMenu(_ items: [DFMenuItem], at point: CGPoint, width: CGFloat = 220) {
        showMenu(items, below: CGRect(origin: point, size: .zero), width: width)
    }

    func show(_ d: DFDialog) {
        menu = nil
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) { dialog = d }
        watchEscape()
    }

    func confirm(_ title: String, _ message: String, confirm: String, destructive: Bool = false, _ action: @escaping () -> Void) {
        show(DFDialog(title: title, message: message, confirm: confirm, destructive: destructive) { _ in action() })
    }

    func prompt(_ title: String, initial: String = "", placeholder: String = "", confirm: String, _ action: @escaping (String) -> Void) {
        show(DFDialog(title: title, field: initial, placeholder: placeholder, confirm: confirm) { action($0) })
    }

    func close() {
        withAnimation(.easeOut(duration: 0.14)) { menu = nil; dialog = nil }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func closeMenu() {
        withAnimation(.easeOut(duration: 0.14)) { menu = nil }
        if dialog == nil, let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }

    private func watchEscape() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.keyCode == 53 else { return e }
            Task { @MainActor in Popups.shared.close() }
            return nil
        }
    }
}

extension View {
    /// Keeps `frame` set to this view's frame in the window, for anchoring a menu to it.
    func popupAnchor(_ frame: Binding<CGRect>) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Popups.space)) } action: { frame.wrappedValue = $0 }
    }

    /// Right-click (or control-click) opens an Oatmeal menu at the pointer.
    func dfContextMenu(_ items: @escaping () -> [DFMenuItem]) -> some View {
        overlay(RightClickCatcher { point in
            let list = items()
            if !list.isEmpty { Popups.shared.showMenu(list, at: point) }
        })
    }
}

/// Sees right-clicks (and control-clicks) only; every other click falls through to SwiftUI.
private struct RightClickCatcher: NSViewRepresentable {
    let action: (CGPoint) -> Void

    final class Catcher: NSView {
        var action: ((CGPoint) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent else { return nil }
            let right = e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
            return right ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with e: NSEvent) { report(e) }
        override func mouseDown(with e: NSEvent) { report(e) }
        private func report(_ e: NSEvent) {
            // The root view fills the window's content (title bar included), so window points are root points.
            guard let content = window?.contentView else { return }
            let p = content.convert(e.locationInWindow, from: nil)
            action?(CGPoint(x: p.x, y: content.isFlipped ? p.y : content.bounds.height - p.y))
        }
    }

    func makeNSView(context: Context) -> Catcher { let v = Catcher(); v.action = action; return v }
    func updateNSView(_ v: Catcher, context: Context) { v.action = action }
}

/// Draws the open menu and dialog over everything. Lives at the top of `RootView`.
struct PopupLayer: View {
    @ObservedObject private var popups = Popups.shared
    @State private var menuSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let m = popups.menu {
                    Color.black.opacity(0.001)
                        .onTapGesture { popups.closeMenu() }
                        .dfContextMenu { popups.closeMenu(); return [] }
                    DFMenuView(items: m.items)
                        .frame(width: m.width)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { menuSize = $0 }
                        .offset(place(m, in: geo.size))
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                        .id(m.id)
                }
                if let d = popups.dialog {
                    Color.black.opacity(0.22).ignoresSafeArea()
                        .onTapGesture { popups.close() }
                        .transition(.opacity)
                    DialogCard(dialog: d)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(popups.menu != nil || popups.dialog != nil)
    }

    private func place(_ m: Popups.Menu, in size: CGSize) -> CGSize {
        let x = min(max(8, m.anchor.minX), size.width - m.width - 8)
        var y = m.anchor.maxY + 6
        if y + menuSize.height > size.height - 8 { y = max(8, m.anchor.minY - 6 - menuSize.height) }
        return CGSize(width: x, height: y)
    }
}

/// The menu card: rows, headers, dividers; submenus slide in with a back row.
private struct DFMenuView: View {
    let items: [DFMenuItem]
    @State private var stack: [(String, [DFMenuItem])] = []

    var body: some View {
        let current = stack.last?.1 ?? items
        VStack(alignment: .leading, spacing: 1) {
            if let top = stack.last {
                MenuRowView(item: .action(top.0, icon: "chevron.left") {}, isBack: true) {
                    withAnimation(.snappy(duration: 0.18)) { _ = stack.popLast() }
                }
                Rectangle().fill(DF.line).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 4)
            }
            ForEach(current.indices, id: \.self) { i in
                let item = current[i]
                switch item.kind {
                case .divider:
                    Rectangle().fill(DF.line).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 4)
                case .header:
                    Text(item.title.uppercased()).font(DF.font(10.5, .bold)).tracking(0.8).foregroundStyle(DF.faint)
                        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 3)
                case .submenu:
                    MenuRowView(item: item) { withAnimation(.snappy(duration: 0.18)) { stack.append((item.title, item.children)) } }
                case .action:
                    MenuRowView(item: item) {
                        Popups.shared.closeMenu()
                        item.perform()
                    }
                }
            }
        }
        .padding(5)
        .background(DF.paper, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(DF.line.opacity(1.4)))
        .shadow(color: Color(hex: 0x3B2A20).opacity(0.14), radius: 18, y: 8)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

private struct MenuRowView: View {
    let item: DFMenuItem
    var isBack = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon = item.icon {
                    Image(systemName: icon).font(.system(size: 11.5, weight: .medium)).frame(width: 16)
                        .foregroundStyle(item.destructive ? DF.tiredInk : (hover ? DF.ink : DF.muted))
                }
                Text(item.title).font(DF.font(13, isBack ? .semibold : .regular))
                    .foregroundStyle(item.destructive ? DF.tiredInk : DF.ink).lineLimit(1)
                Spacer(minLength: 8)
                if let hint = item.hint { Text(hint).font(DF.font(11)).foregroundStyle(DF.faint) }
                if item.checked { Image(systemName: "checkmark").font(.system(size: 10.5, weight: .bold)).foregroundStyle(DF.ink) }
                if item.kind == .submenu { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(DF.faint) }
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(hover ? (item.destructive ? DF.tiredBg : DF.wash.opacity(0.8)) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct DialogCard: View {
    let dialog: DFDialog
    @State private var text = ""
    @FocusState private var focused: Bool

    private var ready: Bool { dialog.field == nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(dialog.title).font(DF.serif(22)).tracking(-0.3)
            if !dialog.message.isEmpty {
                Text(dialog.message).font(DF.font(14)).foregroundStyle(DF.muted).fixedSize(horizontal: false, vertical: true)
            }
            if dialog.field != nil {
                TextField(dialog.placeholder, text: $text)
                    .textFieldStyle(.plain).font(DF.font(15))
                    .focused($focused)
                    .onSubmit(submit)
                    .padding(.horizontal, 11).frame(height: 36)
                    .background(DF.canvas, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(DF.ink.opacity(0.5), lineWidth: 1.5))
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { Popups.shared.close() }.buttonStyle(.df(.ghost, height: 32))
                Button(dialog.confirm, action: submit)
                    .buttonStyle(DestructiveFill(destructive: dialog.destructive))
                    .disabled(!ready)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 400)
        .background(DF.paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DF.line))
        .shadow(color: Color(hex: 0x3B2A20).opacity(0.16), radius: 22, y: 10)
        .onAppear {
            text = dialog.field ?? ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }

    private func submit() {
        guard ready else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Popups.shared.close()
        dialog.onConfirm(value)
    }

    /// The confirm button: ink, or red for deleting.
    private struct DestructiveFill: ButtonStyle {
        let destructive: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(DF.font(13, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 32)
                .background(destructive ? DF.tiredInk : DF.ink, in: RoundedRectangle(cornerRadius: 8))
                .opacity(configuration.isPressed ? 0.85 : 1)
                .contentShape(Rectangle())
        }
    }
}

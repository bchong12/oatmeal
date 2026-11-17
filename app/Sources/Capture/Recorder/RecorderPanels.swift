import AppKit
import AVFoundation
import SwiftUI

/// The recorder's floating pieces, from the Purist frames "Capture · 1 Start" and "Capture · 2 Recording":
/// the start bar, the camera bubble and the recording controls. Non-activating panels over every app and space,
/// left out of the recording itself (Lurker excludes Oatmeal's own windows).
@MainActor
final class RecorderPanels {
    static let shared = RecorderPanels()

    private lazy var bar = FloatingPanel(RecorderBar().environmentObject(RecorderController.shared).environmentObject(CameraFeed.shared), anchor: .bottom(44))
    private lazy var controls = FloatingPanel(RecordingControls().environmentObject(RecorderController.shared).environmentObject(CameraFeed.shared), anchor: .bottom(44))
    private lazy var bubble = BubblePanel()

    func showBar() { controls.hide(); bar.show() }
    func hideBar() { bar.hide() }
    func showControls() { bar.hide(); controls.show() }
    func showBubble(_ on: Bool) { on ? bubble.show() : bubble.hide() }
    func hideAll() { bar.hide(); controls.hide(); bubble.hide() }

    /// Where the bubble sits, in global top-left points (nil when it's hidden).
    func bubbleFrame() -> CGRect? { bubble.globalFrame }
}

/// A borderless panel that sizes itself to its SwiftUI content and stays anchored as that content grows.
@MainActor
final class FloatingPanel {
    enum Anchor { case bottom(CGFloat) }
    private let panel: NSPanel
    private let anchor: Anchor
    private var screen: NSScreen?

    init<V: View>(_ root: V, anchor: Anchor) {
        self.anchor = anchor
        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: AnyView(root.fixedSize().onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in
            MainActor.assumeIsolated { self?.fit(size) }
        }))
        host.sizingOptions = []
        panel.contentView = host
    }

    func show() {
        screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        fit(panel.contentView?.fittingSize ?? panel.frame.size)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    private func fit(_ size: CGSize) {
        guard size.width > 0, size.height > 0, let f = (screen ?? NSScreen.main)?.visibleFrame else { return }
        switch anchor {
        case .bottom(let gap):
            panel.setFrame(NSRect(x: (f.midX - size.width / 2).rounded(), y: f.minY + gap, width: size.width, height: size.height), display: true)
        }
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
}

// MARK: - Start bar

private struct RecorderBar: View {
    @EnvironmentObject var rec: RecorderController
    @EnvironmentObject var feed: CameraFeed
    @State private var open: Menu?
    enum Menu { case camera, mic }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            if let open { picker(open).transition(.opacity.combined(with: .move(edge: .bottom))) }
            if let e = rec.error {
                Text(e).font(DF.font(13)).foregroundStyle(DF.tiredInk).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(DF.tiredBg))
                    .frame(maxWidth: 520).fixedSize(horizontal: false, vertical: true)
            }
            bar
        }
        .padding(16)
        .animation(.easeOut(duration: 0.15), value: open)
    }

    private var bar: some View {
        HStack(spacing: 6) {
            iconButton("xmark", help: "Close") { rec.close() }
            HStack(spacing: 2) {
                modeButton(.area, "Area", "viewfinder")
                modeButton(.window, "Window", "macwindow")
                modeButton(.screen, "Screen", "display")
            }
            .padding(3).background(RoundedRectangle(cornerRadius: 9).fill(DF.wash))
            Rectangle().fill(DF.line).frame(width: 1, height: 22)
            sourceButton(.camera, icon: rec.cameraID == nil ? "video.slash" : "video", title: cameraName, on: rec.cameraID != nil)
            sourceButton(.mic, icon: rec.micID == nil ? "mic.slash" : "mic", title: micName, on: rec.micID != nil, level: rec.micID != nil)
            Button { rec.macSound.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: rec.macSound ? "speaker.wave.2" : "speaker.slash").font(.system(size: 13, weight: .medium))
                    Text("Mac sound").font(DF.font(14, .medium)).fixedSize()
                }
                .foregroundStyle(rec.macSound ? DF.ink : DF.muted)
                .padding(.horizontal, 10).frame(height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(rec.macSound ? "The Mac's sound is recorded" : "The Mac's sound is left out")
            Button { rec.record() } label: {
                HStack(spacing: 8) {
                    Circle().fill(DF.now).frame(width: 9, height: 9)
                    Text("Record").font(DF.font(14, .medium)).fixedSize()
                    Text("fn ⌘").font(DF.font(13)).fixedSize().foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white).padding(.horizontal, 15).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 8).fill(DF.ink))
            }
            .buttonStyle(.plain)
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.1)))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }

    private var cameraName: String {
        rec.cameraID.flatMap { id in feed.cameras.first { $0.uniqueID == id }?.localizedName }.map(short) ?? "No camera"
    }
    private var micName: String {
        rec.micID.flatMap { id in feed.mics.first { $0.uniqueID == id }?.localizedName }.map(short) ?? "No mic"
    }
    /// "FaceTime HD Camera (Built-in)" → "FaceTime HD Camera".
    private func short(_ s: String) -> String {
        let cut = s.components(separatedBy: " (").first ?? s
        return cut.count > 22 ? String(cut.prefix(21)) + "…" : cut
    }

    private func modeButton(_ m: RecorderController.Mode, _ title: String, _ icon: String) -> some View {
        let on = rec.mode == m
        return Button { rec.mode = m } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12.5, weight: .medium))
                Text(title).font(DF.font(14, .medium)).fixedSize()
            }
            .foregroundStyle(on ? DF.ink : DF.muted)
            .padding(.horizontal, 11).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.white : .clear).shadow(color: .black.opacity(on ? 0.1 : 0), radius: 1, y: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sourceButton(_ menu: Menu, icon: String, title: String, on: Bool, level: Bool = false) -> some View {
        Button { open = open == menu ? nil : menu } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
                Text(title).font(DF.font(14, .medium)).fixedSize()
                if level { MicBars(level: feed.level, color: DF.ink) }
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(DF.faint)
            }
            .foregroundStyle(on ? DF.ink : DF.muted)
            .padding(.horizontal, 10).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(open == menu ? DF.wash : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(DF.muted)
                .frame(width: 34, height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    /// The device list, drawn above the bar (no system menus).
    private func picker(_ menu: Menu) -> some View {
        let devices = menu == .camera ? feed.cameras : feed.mics
        let current = menu == .camera ? rec.cameraID : rec.micID
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(devices, id: \.uniqueID) { d in
                row(d.localizedName, on: current == d.uniqueID) {
                    if menu == .camera { rec.cameraID = d.uniqueID } else { rec.micID = d.uniqueID }
                    open = nil
                }
            }
            Rectangle().fill(DF.line).frame(height: 1).padding(.vertical, 3)
            row(menu == .camera ? "No camera" : "No mic", on: current == nil) {
                if menu == .camera { rec.cameraID = nil } else { rec.micID = nil }
                open = nil
            }
        }
        .padding(5)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.1)))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }

    private func row(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(DF.font(14)).foregroundStyle(DF.ink).lineLimit(1)
                Spacer()
                if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(DF.ink) }
            }
            .padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
        }
        .buttonStyle(HoverRow())
    }
}

private struct HoverRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }
    private struct Face: View {
        let configuration: Configuration
        @State private var hover = false
        var body: some View {
            configuration.label.background(RoundedRectangle(cornerRadius: 6).fill(hover ? DF.wash : .clear)).onHover { hover = $0 }
        }
    }
}

/// Four little bars that follow the mic (the recorder's; Settings has its own LevelBars).
struct MicBars: View {
    let level: Float
    var color: Color
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                let lit = level > Float(i) * 0.22
                RoundedRectangle(cornerRadius: 1.5).fill(lit ? color : color.opacity(0.2))
                    .frame(width: 3, height: [5, 9, 13, 8][i])
            }
        }
        .frame(height: 14)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}

// MARK: - Recording controls

private struct RecordingControls: View {
    @EnvironmentObject var rec: RecorderController
    @EnvironmentObject var feed: CameraFeed

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(rec.phase == .paused ? DF.faint : DF.now).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(DF.now.opacity(rec.phase == .paused ? 0 : 0.2), lineWidth: 4))
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let s = Int(rec.elapsed(at: ctx.date))
                    Text(String(format: "%d:%02d", s / 60, s % 60)).font(DF.font(14, .medium)).monospacedDigit().foregroundStyle(DF.ink)
                }
            }
            .padding(.leading, 9).padding(.trailing, 8)
            if rec.micID != nil { MicBars(level: feed.level, color: DF.ink).padding(.trailing, 8) }
            Rectangle().fill(DF.line).frame(width: 1, height: 22)
            button(rec.phase == .paused ? "play.fill" : "pause.fill", rec.phase == .paused ? "Resume" : "Pause") { rec.togglePause() }
            button("arrow.counterclockwise", "Start over") { rec.startOver() }
            iconButton(rec.cameraID == nil ? "video.slash" : "video", help: rec.cameraID == nil ? "Turn the camera on" : "Turn the camera off") { rec.toggleCamera() }
            iconButton("trash", help: "Discard this recording", tint: DF.muted) { rec.discard() }
            Button { rec.stop() } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 9, height: 9)
                    Text("Stop").font(DF.font(14, .medium)).fixedSize()
                    Text("fn ⌘").font(DF.font(13)).fixedSize().foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white).padding(.horizontal, 15).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 8).fill(DF.ink))
            }
            .buttonStyle(.plain)
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.1)))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
        .padding(16)
    }

    private func button(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(DF.font(14, .medium)).fixedSize()
            }
            .foregroundStyle(DF.ink).padding(.horizontal, 10).frame(height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ icon: String, help: String, tint: Color = DF.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
                .frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }
}

// MARK: - Camera bubble

/// Your face in a circle you can drag anywhere; S / M / L on hover. Kept out of the screen recording: the camera is
/// recorded to its own file and the engine draws the bubble, so it never zooms with the screen.
@MainActor
final class BubblePanel {
    private var panel: NSPanel?
    private let d = UserDefaults.standard
    static let sizes: [CGFloat] = [120, 168, 228]

    var globalFrame: CGRect? {
        guard let p = panel, p.isVisible else { return nil }
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let inset = Self.margin
        let f = p.frame.insetBy(dx: inset, dy: inset)
        return CGRect(x: f.minX, y: mainHeight - f.maxY, width: f.width, height: f.height)
    }

    static let margin: CGFloat = 14

    func show() {
        if panel == nil { make() }
        guard let panel else { return }
        if !panel.isVisible {
            let size = Self.sizes[min(2, max(0, d.integer(forKey: "bubble.size") == 0 ? 1 : d.integer(forKey: "bubble.size")))]
            let side = size + Self.margin * 2
            var origin = NSPoint(x: d.double(forKey: "bubble.x"), y: d.double(forKey: "bubble.y"))
            if origin == .zero || !NSScreen.screens.contains(where: { $0.frame.contains(origin) }) {
                let f = (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)?.visibleFrame ?? .zero
                origin = NSPoint(x: f.minX + 28, y: f.minY + 28)
            }
            panel.setFrame(NSRect(origin: origin, size: NSSize(width: side, height: side)), display: true)
        }
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func make() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 196, height: 196), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: BubbleView(
            move: { [weak self, weak p] delta in
                guard let p else { return }
                p.setFrameOrigin(NSPoint(x: p.frame.minX + delta.width, y: p.frame.minY - delta.height))
                self?.remember()
            },
            resize: { [weak self, weak p] index in
                guard let p, let self else { return }
                self.d.set(index, forKey: "bubble.size")
                let side = Self.sizes[index] + Self.margin * 2
                let c = NSPoint(x: p.frame.midX, y: p.frame.midY)
                p.setFrame(NSRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side), display: true, animate: true)
                self.remember()
            }))
        panel = p
    }

    private func remember() {
        guard let p = panel else { return }
        d.set(p.frame.minX, forKey: "bubble.x"); d.set(p.frame.minY, forKey: "bubble.y")
    }
}

private struct BubbleView: View {
    let move: (CGSize) -> Void
    let resize: (Int) -> Void
    @State private var hover = false
    @State private var last: CGSize = .zero

    var body: some View {
        GeometryReader { g in
            let side = g.size.width - BubblePanel.margin * 2
            ZStack(alignment: .bottom) {
                CameraPreview()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous).strokeBorder(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                if hover {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Button { resize(i) } label: {
                                Text(["S", "M", "L"][i]).font(DF.font(11, .semibold)).foregroundStyle(DF.ink)
                                    .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.95)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .frame(width: side, height: side)
            .position(x: g.size.width / 2, y: g.size.height / 2)
            .contentShape(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous))
            .onHover { hover = $0 }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { v in move(CGSize(width: v.translation.width - last.width, height: v.translation.height - last.height)); last = v.translation }
                .onEnded { _ in last = .zero })
        }
    }
}

/// The live camera, mirrored like a selfie view.
private struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: CameraFeed.shared.session)
        layer.videoGravity = .resizeAspectFill
        if let c = layer.connection, c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = true }
        layer.backgroundColor = NSColor(white: 0.93, alpha: 1).cgColor
        v.layer = layer
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        if let layer = v.layer as? AVCaptureVideoPreviewLayer, let c = layer.connection, c.isVideoMirroringSupported, !c.isVideoMirrored {
            c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = true
        }
    }
}

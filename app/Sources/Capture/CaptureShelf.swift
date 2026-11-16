import SwiftUI
import AppKit

/// The shelf: recent captures stacked at the bottom right of the screen, there
/// until you clear them (macOS's thumbnail slides off after a few seconds).
/// A non-activating panel, so clicking a capture leaves the app you were in at
/// the front and the paste lands there.
@MainActor
final class CaptureShelf {
    static let shared = CaptureShelf()
    private var panel: NSPanel?

    private static let width: CGFloat = 236

    /// Just as tall as its cards, so the shelf never sits over clicks meant for what is behind it.
    private var height: CGFloat {
        let n = CGFloat(CaptureService.shared.shelf.count)
        return n * 140 + (n > 1 ? 34 : 0) + (CaptureService.shared.recordingSince != nil ? 44 : 0) + 8
    }

    func show() {
        if panel == nil { make() }
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            panel.setFrame(NSRect(x: f.maxX - Self.width - 12, y: f.minY + 12, width: Self.width, height: height), display: true)
        }
        panel.orderFrontRegardless()
    }

    /// After a card leaves: shrink to what is left, keeping the bottom edge.
    func fit() {
        guard let panel, panel.isVisible else { return }
        var f = panel.frame
        f.size.height = height
        panel.setFrame(f, display: true, animate: false)
    }

    func hide() { panel?.orderOut(nil) }

    /// macOS drops the shelf when you change spaces or go into a full-screen app,
    /// even though it joins all spaces, so put it back in front each time.
    private func keepInFront() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                /* Once the switch has settled. Ordering a panel AppKit still counts as visible to
                   the front does nothing, so take it off first: it comes back on the space now showing. */
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    MainActor.assumeIsolated {
                        guard let panel = self.panel, panel.isVisible,
                              !CaptureService.shared.shelf.isEmpty || CaptureService.shared.recordingSince != nil else { return }
                        panel.orderOut(nil)
                        panel.orderFrontRegardless()
                    }
                }
            }
        }
    }

    private func make() {
        keepInFront()
        let p = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: CaptureShelfView().environmentObject(CaptureService.shared))
        panel = p
    }
}

private final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct CaptureShelfView: View {
    @EnvironmentObject var captures: CaptureService

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Spacer(minLength: 0)
            ForEach(captures.shelf.reversed()) { c in
                CaptureCard(capture: c)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            if let since = captures.recordingSince {
                RecordingChip(since: since)
            }
            if captures.shelf.count > 1 {
                Button("Clear all") { withAnimation(.easeOut(duration: 0.2)) { captures.clearShelf() } }
                    .buttonStyle(.plain)
                    .font(DF.font(11, .medium))
                    .foregroundStyle(DF.muted)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(DF.paper).shadow(color: .black.opacity(0.12), radius: 6, y: 2))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(4)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: captures.shelf)
    }
}

/// While recording: how long, and Stop (as does fn ⌘ again).
private struct RecordingChip: View {
    let since: Date
    @EnvironmentObject var captures: CaptureService

    var body: some View {
        Button { captures.toggleRecording() } label: {
            HStack(spacing: 8) {
                Circle().fill(DF.now).frame(width: 8, height: 8)
                TimelineView(.periodic(from: since, by: 1)) { ctx in
                    let s = max(0, Int(ctx.date.timeIntervalSince(since)))
                    Text(String(format: "%d:%02d", s / 60, s % 60)).font(DF.font(13, .medium)).monospacedDigit().foregroundStyle(.white)
                }
                Text("Stop").font(DF.font(13, .semibold)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 14).frame(height: 36)
            .background(Capsule().fill(DF.espresso))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .help("Stop recording (fn ⌘)")
    }
}

private struct CaptureCard: View {
    let capture: Capture
    @EnvironmentObject var captures: CaptureService
    @State private var hover = false
    @State private var pasted = false
    /// How far the card has been swiped to the right.
    @State private var swipe: CGFloat = 0

    var body: some View {
        card
            .offset(x: swipe)
            .opacity(1 - min(swipe / 220, 0.7))
    }

    private var card: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                thumbnail
                    .frame(width: 220, height: 132)
                    .clipped()
                HStack(spacing: 5) {
                    Image(systemName: pasted ? "checkmark" : capture.kind == .recording ? "video.fill" : "camera.fill").font(.system(size: 10, weight: .semibold))
                    Text(pasted ? "Pasted" : hover ? "Click to paste · drag to drop" : capture.kind == .recording ? "Recording" : "Screenshot").font(DF.font(11, .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            /* Click to paste; drag it into an app and it leaves the shelf, as macOS's own thumbnail does.
               Swipe it right (mouse or two fingers) to put it away, like a notification. */
            .overlay(DragArea(files: captures.files(capture), picture: capture.picture, onClick: paste,
                              onDropped: { withAnimation(.easeOut(duration: 0.2)) { captures.remove(capture) } },
                              onSwipe: { swipe = max(0, $0) }, onSwipeEnd: endSwipe))
            .help("Click to paste into \(captures.targetApp?.localizedName ?? "the app you were in"). Drag to drop it anywhere. Swipe right to put it away.")

            if hover {
                HStack(spacing: 4) {
                    icon("doc.on.doc", "Copy") { captures.copy(capture) }
                    icon("folder", "Show in Finder") { captures.reveal(capture) }
                    icon("xmark", "Remove from the shelf") { withAnimation { captures.remove(capture) } }
                }
                .padding(6)
                .transition(.opacity)
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }

    @ViewBuilder private var thumbnail: some View {
        if let url = capture.picture, let img = NSImage(contentsOf: url) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            DF.espresso.overlay(Image(systemName: "video").foregroundStyle(.white.opacity(0.6)))
        }
    }

    private func icon(_ name: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 10, weight: .semibold)).foregroundStyle(DF.ink)
                .frame(width: 22, height: 22).background(Circle().fill(DF.paper.opacity(0.95)))
        }
        .buttonStyle(.plain).help(help)
    }

    /// Far enough (or flicked): slide off and leave the shelf. Otherwise spring back.
    private func endSwipe(_ velocity: CGFloat) {
        if swipe > 70 || velocity > 600 {
            withAnimation(.easeOut(duration: 0.18)) { swipe = 280 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { captures.remove(capture) }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { swipe = 0 }
        }
    }

    private func paste() {
        captures.paste(capture)
        withAnimation { pasted = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { pasted = false } }
    }
}

/// The card's click and drag, in AppKit: SwiftUI's drag has no way to know a
/// drop happened, and a capture dropped somewhere should leave the shelf.
private struct DragArea: NSViewRepresentable {
    let files: [URL]
    let picture: URL?
    let onClick: () -> Void
    let onDropped: () -> Void
    /// The swipe so far (points to the right), then its end with the speed it ended at.
    let onSwipe: (CGFloat) -> Void
    let onSwipeEnd: (CGFloat) -> Void

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }
    func updateNSView(_ v: DragSourceView, context: Context) {
        v.files = files; v.picture = picture; v.onClick = onClick; v.onDropped = onDropped
        v.onSwipe = onSwipe; v.onSwipeEnd = onSwipeEnd
    }
}

/// A press that heads right is a swipe (put it away); one that heads any other
/// way is a drag of the file. Two fingers sideways on a trackpad swipe too.
private final class DragSourceView: NSView, NSDraggingSource {
    var files: [URL] = []
    var picture: URL?
    var onClick: () -> Void = {}
    var onDropped: () -> Void = {}
    var onSwipe: (CGFloat) -> Void = { _ in }
    var onSwipeEnd: (CGFloat) -> Void = { _ in }
    private var downAt: NSPoint?
    private var dragging = false
    private var swiping = false
    private var last: (x: CGFloat, time: TimeInterval) = (0, 0)
    private var speed: CGFloat = 0
    private var scrolled: CGFloat = 0

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow; dragging = false; swiping = false }

    override func mouseDragged(with event: NSEvent) {
        guard let d = downAt, !dragging else { return }
        let dx = event.locationInWindow.x - d.x, dy = event.locationInWindow.y - d.y
        if swiping { track(dx, at: event.timestamp); return }
        guard hypot(dx, dy) > 4 else { return }
        if dx > 0, dx > abs(dy) {
            swiping = true
            last = (dx, event.timestamp)
            track(dx, at: event.timestamp)
            return
        }
        dragging = true
        let image = picture.flatMap { NSImage(contentsOf: $0) } ?? NSImage(systemSymbolName: "video", accessibilityDescription: nil) ?? NSImage()
        let items: [NSDraggingItem] = files.enumerated().map { i, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let w: CGFloat = 160, h = image.size.width > 0 ? w * image.size.height / image.size.width : 100
            let p = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: p.x - w / 2 + CGFloat(i) * 8, y: p.y - h / 2 - CGFloat(i) * 8, width: w, height: h), contents: i == 0 ? image : nil)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    private func track(_ x: CGFloat, at time: TimeInterval) {
        if time > last.time { speed = (x - last.x) / CGFloat(time - last.time) }
        last = (x, time)
        onSwipe(x)
    }

    override func mouseUp(with event: NSEvent) {
        if swiping { onSwipeEnd(speed) }
        else if !dragging, downAt != nil { onClick() }
        downAt = nil
        swiping = false
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        if event.phase == .began { scrolled = 0; speed = 0 }
        /* Which way the fingers moved, whatever the natural-scrolling setting. */
        let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        if event.phase == .ended || event.phase == .cancelled {
            if scrolled != 0 { onSwipeEnd(speed) }
            scrolled = 0
            return
        }
        guard scrolled != 0 || abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        scrolled = max(0, scrolled + dx)
        speed = dx * 60
        onSwipe(scrolled)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        downAt = nil
        if !operation.isEmpty { onDropped() }
    }
}

import AppKit

/// Drag a box over what to record, the way a screenshot's selection works
/// (macOS's recorder has no selection of its own from the command line): a
/// crosshair and the box, nothing else. A click records the whole screen under
/// the pointer; Esc cancels.
/// Hands back the box in screencapture's coordinates: points, from the top
/// left of the main display.
@MainActor
final class RegionPicker {
    static let shared = RegionPicker()
    private var panels: [NSPanel] = []
    private var done: ((CGRect?) -> Void)?

    func pick(_ completion: @escaping (CGRect?) -> Void) {
        guard panels.isEmpty else { return }
        done = completion
        for screen in NSScreen.screens {
            let p = PickerPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .screenSaver
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let view = PickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.screenFrame = screen.frame
            view.finish = { [weak self] rect in self?.finish(rect) }
            p.contentView = view
            p.setFrame(screen.frame, display: true)
            p.makeKeyAndOrderFront(nil)
            panels.append(p)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
    }

    /// `rect` in AppKit screen coordinates (bottom-left origin), or nil when cancelled.
    private func finish(_ rect: CGRect?) {
        NSCursor.pop()
        for p in panels { p.orderOut(nil) }
        panels = []
        let main = NSScreen.screens.first?.frame ?? .zero
        let out = rect.map { r in CGRect(x: r.minX, y: main.maxY - r.maxY, width: r.width, height: r.height).integral }
        let cb = done
        done = nil
        cb?(out)
    }
}

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class PickerView: NSView {
    var screenFrame: CGRect = .zero
    var finish: ((CGRect?) -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish?(nil) } else { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); current = start; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { current = convert(event.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        guard let s = start, let c = current else { return }
        let local = box(s, c)
        if local.width < 8 || local.height < 8 {
            finish?(screenFrame)   // a click: the whole screen
        } else {
            finish?(local.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY))
        }
    }

    private func box(_ a: NSPoint, _ b: NSPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    /// Like macOS's own screenshot drag: nothing on screen but the crosshair,
    /// and a light box where you drag. (The near-clear fill is what lets the
    /// window take the mouse; fully clear, clicks would fall through.)
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.002).setFill()
        bounds.fill()
        guard let s = start, let c = current else { return }
        let r = box(s, c)
        NSColor.white.withAlphaComponent(0.18).setFill()
        r.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let edge = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
        edge.lineWidth = 1
        edge.stroke()
    }
}

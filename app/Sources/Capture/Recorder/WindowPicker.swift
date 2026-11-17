import AppKit

/// Window mode: the window under the pointer lights up; click it to record it, Esc to cancel.
/// Hands back its CGWindowID (Lurker films covered windows fine, so it needn't stay in front).
@MainActor
final class WindowPicker {
    static let shared = WindowPicker()
    private var panels: [NSPanel] = []
    private var done: ((CGWindowID?) -> Void)?

    func pick(_ completion: @escaping (CGWindowID?) -> Void) {
        guard panels.isEmpty else { return }
        done = completion
        let windows = Self.windows()
        for screen in NSScreen.screens {
            let p = Panel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .screenSaver
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let v = HighlightView(frame: NSRect(origin: .zero, size: screen.frame.size))
            v.screenFrame = screen.frame
            v.windows = windows
            v.finish = { [weak self] id in self?.finish(id) }
            p.contentView = v
            p.acceptsMouseMovedEvents = true
            p.setFrame(screen.frame, display: true)
            p.makeKeyAndOrderFront(nil)
            panels.append(p)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ id: CGWindowID?) {
        for p in panels { p.orderOut(nil) }
        panels = []
        let cb = done
        done = nil
        cb?(id)
    }

    struct Window { let id: CGWindowID; let frame: CGRect; let app: String }

    /// On-screen app windows front to back, frames in global top-left points, leaving out Oatmeal's own.
    static func windows() -> [Window] {
        let me = ProcessInfo.processInfo.processIdentifier
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        return list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let frame = CGRect(dictionaryRepresentation: b as CFDictionary),
                  frame.width >= 80, frame.height >= 60 else { return nil }
            return Window(id: id, frame: frame, app: w[kCGWindowOwnerName as String] as? String ?? "")
        }
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private final class HighlightView: NSView {
        var screenFrame: CGRect = .zero
        var windows: [Window] = []
        var finish: ((CGWindowID?) -> Void)?
        private var hovered: Window?
        private var tracking: NSTrackingArea?

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

        override func updateTrackingAreas() {
            if let tracking { removeTrackingArea(tracking) }
            let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(t); tracking = t
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { finish?(nil) } else { super.keyDown(with: event) }
        }

        /// Global top-left point under the mouse.
        private func globalPoint() -> CGPoint {
            let m = NSEvent.mouseLocation
            let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
            return CGPoint(x: m.x, y: mainHeight - m.y)
        }

        override func mouseMoved(with event: NSEvent) {
            let p = globalPoint()
            let hit = windows.first { $0.frame.contains(p) }
            if hit?.id != hovered?.id { hovered = hit; needsDisplay = true }
        }

        override func mouseDown(with event: NSEvent) {
            mouseMoved(with: event)
            finish?(hovered?.id)
        }

        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.002).setFill()
            bounds.fill()
            guard let w = hovered else { return }
            // global top-left → this view's bottom-left
            let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
            let r = CGRect(x: w.frame.minX - screenFrame.minX, y: mainHeight - w.frame.maxY - screenFrame.minY, width: w.frame.width, height: w.frame.height)
            NSColor(white: 0, alpha: 0.10).setFill()
            NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
            NSColor(white: 0.1, alpha: 0.9).setStroke()
            let edge = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
            edge.lineWidth = 2
            edge.stroke()
            let label = "Record \(w.app.isEmpty ? "this window" : w.app)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
            let size = label.size(withAttributes: attrs)
            let pill = CGRect(x: r.midX - size.width / 2 - 12, y: r.midY - 15, width: size.width + 24, height: 30)
            NSColor(white: 0.1, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
            label.draw(at: CGPoint(x: pill.minX + 12, y: pill.minY + (30 - size.height) / 2), withAttributes: attrs)
        }
    }
}

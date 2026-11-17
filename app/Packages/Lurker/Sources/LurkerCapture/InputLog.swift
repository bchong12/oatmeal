import AppKit
import CoreMedia

/// events.jsonl: every mouse move (no throttling), button down/up with click counts and modifiers, scrolls, cursor shape
/// changes (each shape's image saved once to cursors/), window moves and, when allowed, keystrokes.
/// `t` is seconds from the take's zero on the host clock; x/y are global points, top-left origin.
/// Mouse logging needs no permission; keys need Accessibility.
final class InputLog: @unchecked Sendable {
    let url: URL
    let cursorDir: URL
    private let zero: Double
    private let windowID: CGWindowID?
    private let logKeys: Bool
    private let q = DispatchQueue(label: "lurker.capture.events")
    private var handle: FileHandle?
    private var monitors: [Any] = []
    private var poll: Timer?
    private var lastCursor = ""
    private var lastCursorCheck = 0.0
    private var knownCursors = Set<String>()
    private var lastFrame = CGRect.null
    private var paused = false
    private(set) var rows = 0

    init(directory: URL, zero: Double, rect: CGRect, scale: CGFloat, windowID: CGWindowID?, keys: Bool, virtualCursor: Bool) throws {
        url = directory.appending(path: "events.jsonl")
        cursorDir = directory.appending(path: "cursors", directoryHint: .isDirectory)
        self.zero = zero; self.windowID = windowID
        logKeys = keys && AXIsProcessTrusted() && !virtualCursor
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        write(["type": "start", "rect": ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height],
               "scale": scale, "windowId": windowID.map { Int($0) } ?? NSNull(), "keys": logKeys,
               "cursor": virtualCursor ? "virtual" : "real", "clock": "host seconds from take zero"], at: 0)
        let virtualOnly = virtualCursor
        Task { @MainActor [self] in
            if !virtualOnly {
                var mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                                   .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
                if logKeys { mask.formUnion([.keyDown, .keyUp]) }
                if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in MainActor.assumeIsolated { self?.handle(e) } }) { monitors.append(m) }
                // our own windows don't reach the global monitor
                if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in MainActor.assumeIsolated { self?.handle(e) }; return e }) { monitors.append(m) }
            }
            // window moves, and cursor shape changes that happen without the mouse moving
            poll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.checkWindow()
                    if !virtualOnly { self.trackCursor(at: HostClock.seconds - self.zero) }
                }
            }
        }
    }

    func setPaused(_ p: Bool) {
        q.async { self.paused = p }
        write(["type": p ? "pause" : "resume"])
    }

    @MainActor private func handle(_ e: NSEvent) {
        let t = e.timestamp - zero
        let p = NSEvent.mouseLocation
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        var row: [String: Any] = ["x": (p.x * 10).rounded() / 10, "y": ((primaryH - p.y) * 10).rounded() / 10]
        let mods = Self.modifiers(e.modifierFlags)
        if !mods.isEmpty { row["mods"] = mods }
        switch e.type {
        case .mouseMoved: row["type"] = "move"
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: row["type"] = "drag"
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: row["type"] = "down"; row["button"] = Self.button(e); row["clicks"] = e.clickCount
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: row["type"] = "up"; row["button"] = Self.button(e)
        case .scrollWheel: row["type"] = "scroll"; row["dx"] = e.scrollingDeltaX; row["dy"] = e.scrollingDeltaY
        case .keyDown, .keyUp:
            row = ["type": e.type == .keyDown ? "key" : "keyup", "chars": e.charactersIgnoringModifiers ?? "", "code": Int(e.keyCode), "repeat": e.isARepeat]
            if !mods.isEmpty { row["mods"] = mods }
        default: return
        }
        if e.type != .keyDown && e.type != .keyUp { trackCursor(at: t) }
        write(row, at: t)
    }

    /// Logs the cursor shape when it changes and saves each shape's image once.
    @MainActor private func trackCursor(at t: Double) {
        guard t - lastCursorCheck > 0.03 else { return }
        lastCursorCheck = t
        guard let c = NSCursor.currentSystem, let tiff = c.image.tiffRepresentation else { return }
        let id = Self.shapeID(c, tiff)
        guard id != lastCursor else { return }
        lastCursor = id
        if !knownCursors.contains(id) {
            knownCursors.insert(id)
            try? FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)
            if let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: cursorDir.appending(path: "\(id).png"))
            }
            write(["type": "cursor-shape", "id": id, "hotX": c.hotSpot.x, "hotY": c.hotSpot.y, "width": c.image.size.width,
                   "height": c.image.size.height, "pixelWidth": NSBitmapImageRep(data: tiff)?.pixelsWide ?? 0], at: t)
        }
        write(["type": "cursor", "id": id], at: t)
    }

    @MainActor private func checkWindow() {
        guard let windowID, let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]])?.first,
              let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { return }
        let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        guard r != lastFrame else { return }
        lastFrame = r
        write(["type": "window", "x": r.minX, "y": r.minY, "width": r.width, "height": r.height])
    }

    /// Writes one row. `t` defaults to now; rows logged while paused are dropped (except pause/resume themselves).
    func write(_ row: [String: Any], at t: Double? = nil) {
        var r = row
        r["t"] = ((t ?? (HostClock.seconds - zero)) * 1000).rounded() / 1000
        let type = row["type"] as? String ?? ""
        guard let line = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]) else { return }
        q.async {
            if self.paused && type != "pause" && type != "resume" && type != "marker" { return }
            self.handle?.write(line); self.handle?.write(Data([0x0A]))
            self.rows += 1
        }
    }

    func stop() async {
        await MainActor.run {
            for m in monitors { NSEvent.removeMonitor(m) }
            monitors = []; poll?.invalidate(); poll = nil
        }
        q.sync { try? handle?.close(); handle = nil }
    }

    static func modifiers(_ f: NSEvent.ModifierFlags) -> [String] {
        var m: [String] = []
        if f.contains(.command) { m.append("command") }
        if f.contains(.shift) { m.append("shift") }
        if f.contains(.option) { m.append("option") }
        if f.contains(.control) { m.append("control") }
        if f.contains(.function) { m.append("function") }
        return m
    }

    @MainActor static func button(_ e: NSEvent) -> String {
        switch e.type {
        case .leftMouseDown, .leftMouseUp: "left"
        case .rightMouseDown, .rightMouseUp: "right"
        default: "other-\(e.buttonNumber)"
        }
    }

    /// Named system cursors keep readable ids; anything else is hashed from its image.
    @MainActor static func shapeID(_ c: NSCursor, _ tiff: Data) -> String {
        let named: [(NSCursor, String)] = [(.arrow, "arrow"), (.iBeam, "iBeam"), (.pointingHand, "pointingHand"), (.closedHand, "closedHand"),
                                           (.openHand, "openHand"), (.crosshair, "crosshair"), (.resizeLeftRight, "resizeLeftRight"),
                                           (.resizeUpDown, "resizeUpDown"), (.operationNotAllowed, "notAllowed"), (.dragCopy, "dragCopy")]
        for (n, name) in named where n.image.tiffRepresentation == tiff { return name }
        var h: UInt64 = 1469598103934665603
        for b in tiff { h = (h ^ UInt64(b)) &* 1099511628211 }
        return "custom-" + String(h, radix: 16)
    }
}

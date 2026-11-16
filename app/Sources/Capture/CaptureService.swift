import AppKit
import AVFoundation

/// One screenshot or screen recording, kept in `CaptureService.folder`.
struct Capture: Identifiable, Equatable {
    enum Kind: String { case shot, recording }
    let url: URL
    let kind: Kind
    let date: Date
    /// For a recording: its frames on one picture, so an agent can see it.
    var frames: URL?
    var id: String { url.lastPathComponent }
    /// What an agent can look at: the picture, or a recording's frames.
    var picture: URL? { kind == .shot ? url : frames }
}

/// Screenshots and screen recordings for handing to an agent.
///
/// macOS's own capture drops a floating thumbnail that slides away after a few
/// seconds, into a temp file that is gone by the time you want it. Here a
/// capture lands in ~/Pictures/Oatmeal and stays on a shelf until you clear
/// it: click it and it is pasted into the app you were in (a file path for a
/// terminal agent, the file for an app that takes files), drag it anywhere,
/// or let the agent fetch it over Oatmeal's MCP server (`get_capture`).
///
/// fn + Space is a region screenshot, macOS's own selection; fn + ⌘ is a
/// recording of a region you drag (RegionPicker), and fn + ⌘ again (or Stop on
/// the shelf) ends it. RightOptionKey's tap hears them, clear of the voice keys.
@MainActor
final class CaptureService: ObservableObject {
    static let shared = CaptureService()

    /// On the shelf, newest first.
    @Published private(set) var shelf: [Capture] = []
    /// The app that was in front when the capture began: where a click pastes.
    @Published private(set) var targetApp: NSRunningApplication?
    /// While a recording runs: when it began.
    @Published private(set) var recordingSince: Date?

    private var running: Process?

    /// No spaces in the folder or the names, so a pasted path works as-is in a terminal.
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Oatmeal", isDirectory: true)
    }

    private init() {}

    /// At launch: frames for any recording dropped into the folder by hand.
    func start() {
        backfillFrames()
        // Dev: `-captures shelf` puts the newest captures on the shelf, for checking it on screen.
        // `-captures shot` takes a whole-screen screenshot down the real path, no selection needed.
        switch UserDefaults.standard.string(forKey: "captures") {
        case "shelf":
            shelf = Array(all().prefix(2))
            if !shelf.isEmpty { CaptureShelf.shared.show() }
        case "shot":
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.capture(["-x"], ext: "png") }
        default: break
        }
    }

    /// A recording dropped into the folder by hand gets its frames too.
    private func backfillFrames() {
        let missing = all().filter { $0.kind == .recording && $0.frames == nil }
        guard !missing.isEmpty else { return }
        Task { for c in missing { _ = await Self.contactSheet(for: c.url) } }
    }

    // MARK: Capturing

    /// A region (or, with space, a window) screenshot.
    func screenshot() {
        guard recordingSince == nil else { return }
        capture(["-i", "-x"], ext: "png")
    }

    /// Start a recording (drag over what to record, or click for the whole
    /// screen), or stop the one running. Stopping is ⌃C to screencapture,
    /// which closes the video properly.
    func toggleRecording() {
        if recordingSince != nil, let p = running { DFLog.log("capture", "stopping the recording"); p.interrupt(); return }
        guard running == nil else { return }
        rememberTarget()
        RegionPicker.shared.pick { [weak self] rect in
            guard let self, let r = rect else { return }
            self.targetApp?.activate()
            self.capture(["-v", "-k", "-x", "-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"], ext: "mov", recording: true)
        }
    }

    /// The app in front, where a click on the shelf will paste (never Oatmeal itself).
    private func rememberTarget() {
        if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier { targetApp = app }
    }

    private func capture(_ flags: [String], ext: String, recording: Bool = false) {
        guard running == nil else { return }
        if !recording { rememberTarget() }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let stamp = Self.stamp.string(from: Date())
        let want = Self.folder.appendingPathComponent("capture-\(stamp).\(ext)")
        let started = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = flags + [want.path]
        p.terminationHandler = { proc in
            DFLog.log("capture", "screencapture ended (status \(proc.terminationStatus))")
            Task { @MainActor in
                self.running = nil
                self.recordingSince = nil
                await self.collect(want: want, since: started)
            }
        }
        do {
            try p.run(); running = p
            DFLog.log("capture", recording ? "recording started" : "screenshot started")
            if recording { recordingSince = started; CaptureShelf.shared.show() }
        } catch { print("[Capture] screencapture failed: \(error)") }
    }

    /// What the capture left: the file asked for, or, when the toolbar saved
    /// to macOS's own place instead, the newest screenshot or recording there,
    /// moved into the folder.
    private func collect(want: URL, since: Date) async {
        var found: URL? = FileManager.default.fileExists(atPath: want.path) ? want : nil
        if found == nil, let stray = Self.newestSystemCapture(since: since) {
            let dest = Self.folder.appendingPathComponent("capture-\(Self.stamp.string(from: since)).\(stray.pathExtension.lowercased())")
            if (try? FileManager.default.moveItem(at: stray, to: dest)) != nil { found = dest }
        }
        DFLog.log("capture", found.map { "kept \($0.lastPathComponent)" } ?? "nothing kept (cancelled)")
        guard var url = found else {   // cancelled, or sent to the clipboard with ⌃
            if shelf.isEmpty { CaptureShelf.shared.hide() } else { CaptureShelf.shared.fit() }
            return
        }
        /* The toolbar can take a screenshot too, written under the .mov name asked for. */
        if url.pathExtension.lowercased() == "mov", let head = try? FileHandle(forReadingFrom: url).read(upToCount: 8),
           head.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            let png = url.deletingPathExtension().appendingPathExtension("png")
            if (try? FileManager.default.moveItem(at: url, to: png)) != nil { url = png }
        }
        let isVideo = ["mov", "mp4"].contains(url.pathExtension.lowercased())
        var c = Capture(url: url, kind: isVideo ? .recording : .shot, date: since)
        if isVideo { c.frames = await Self.contactSheet(for: url) }
        shelf.insert(c, at: 0)
        if shelf.count > 3 { shelf.removeLast(shelf.count - 3) }
        CaptureShelf.shared.show()
    }

    /// macOS's screenshot location (Desktop unless changed), for a capture the toolbar saved there.
    private static func newestSystemCapture(since: Date) -> URL? {
        let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let dir = custom.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files
            .filter { ["png", "jpg", "mov", "mp4"].contains($0.pathExtension.lowercased()) }
            .compactMap { u -> (URL, Date)? in
                guard let d = try? u.resourceValues(forKeys: [.creationDateKey]).creationDate, d >= since.addingTimeInterval(-1) else { return nil }
                return (u, d)
            }
            .max { $0.1 < $1.1 }?.0
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HH.mm.ss"
        return f
    }()

    // MARK: A recording's frames

    /// Up to twelve evenly spaced frames on one picture, four across, each
    /// with its time, saved beside the recording as …-frames.png.
    static func contactSheet(for video: URL) async -> URL? {
        let asset = AVURLAsset(url: video)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return nil }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
        let count = max(2, min(12, Int(duration.seconds.rounded(.up))))
        var frames: [(CGImage, Double)] = []
        for i in 0..<count {
            let t = duration.seconds * (Double(i) + 0.5) / Double(count)
            if let (img, _) = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)) { frames.append((img, t)) }
        }
        guard let first = frames.first?.0 else { return nil }
        let cols = min(4, frames.count), rows = Int((Double(frames.count) / Double(cols)).rounded(.up))
        let cellW = 480.0, cellH = cellW * Double(first.height) / Double(max(1, first.width)), gap = 8.0, label = 22.0
        let size = CGSize(width: Double(cols) * cellW + Double(cols + 1) * gap, height: Double(rows) * (cellH + label) + Double(rows + 1) * gap)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (i, (img, t)) in frames.enumerated() {
            let col = i % cols, row = i / cols
            let x = gap + Double(col) * (cellW + gap)
            let yTop = size.height - gap - Double(row) * (cellH + label + gap)
            ctx.draw(img, in: CGRect(x: x, y: yTop - cellH, width: cellW, height: cellH))
            let text = String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) as NSString
            text.draw(at: NSPoint(x: x, y: yTop - cellH - label + 4),
                      withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor(white: 0.85, alpha: 1)])
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let out = ctx.makeImage(), let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else { return nil }
        let dest = video.deletingPathExtension().appendingPathExtension("frames.png")
        return (try? png.write(to: dest)) != nil ? dest : nil
    }

    // MARK: Handing it over

    /// Paste into the app you were in: its path as text (what a terminal agent
    /// reads) and the file itself (what an app that takes files reads). A
    /// recording goes over as its frames first, then the video.
    func paste(_ c: Capture) {
        put(c)
        if let app = targetApp, !app.isActive { app.activate() }
        guard TextInserter.isTrusted(prompt: true) else { return }   // left on the clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Self.postPaste() }
    }

    /// On the clipboard only, for pasting by hand.
    func copy(_ c: Capture) { put(c) }

    func reveal(_ c: Capture) { NSWorkspace.shared.activateFileViewerSelecting([c.url]) }

    /// The files a capture hands over: a recording's frames first, then the video.
    func files(_ c: Capture) -> [URL] { c.kind == .recording ? [c.frames, c.url].compactMap { $0 } : [c.url] }

    func remove(_ c: Capture) {
        shelf.removeAll { $0.id == c.id }
        if shelf.isEmpty { CaptureShelf.shared.hide() } else { CaptureShelf.shared.fit() }
    }

    func clearShelf() { shelf.removeAll(); CaptureShelf.shared.hide() }

    private func put(_ c: Capture) {
        let files = files(c)
        let pb = NSPasteboard.general
        pb.clearContents()
        let text = files.map(\.path).joined(separator: " ")
        let items: [NSPasteboardItem] = files.enumerated().map { i, url in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            if i == 0 {
                item.setString(text, forType: .string)
                if url.pathExtension.lowercased() == "png", let data = try? Data(contentsOf: url) { item.setData(data, forType: .png) }
            }
            return item
        }
        pb.writeObjects(items)
    }

    private static func postPaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: For the MCP server

    /// Every capture in the folder, newest first (the shelf is only the recent few).
    func all() -> [Capture] {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let byName = Set(files.map(\.lastPathComponent))
        return files.compactMap { url -> Capture? in
            let ext = url.pathExtension.lowercased(), name = url.lastPathComponent
            if name.hasSuffix(".frames.png") { return nil }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if ext == "png" || ext == "jpg" { return Capture(url: url, kind: .shot, date: date) }
            guard ext == "mov" || ext == "mp4" else { return nil }
            let framesName = url.deletingPathExtension().lastPathComponent + ".frames.png"
            return Capture(url: url, kind: .recording, date: date, frames: byName.contains(framesName) ? url.deletingLastPathComponent().appendingPathComponent(framesName) : nil)
        }.sorted { $0.date > $1.date }
    }
}

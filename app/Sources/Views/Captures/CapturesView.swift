import SwiftUI
import AVFoundation
import AppKit

/// Captures: every screenshot and recording, newest first, like the Purist frame "Capture · 4 In the app".
/// A grid you can filter and search (recordings by what was said); open one for the player, Raw or Polished,
/// its transcript, and paste / show in Finder / delete.
struct CapturesView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var service = CaptureService.shared
    @State private var items: [Capture] = []
    @State private var filter: Filter = .all
    @State private var query = ""

    enum Filter: Hashable { case all, recordings, screenshots }

    private var shown: [Capture] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return items.filter { c in
            switch filter {
            case .all: true
            case .recordings: c.kind == .recording
            case .screenshots: c.kind == .shot
            }
        }.filter { c in
            q.isEmpty || (c.title ?? "").lowercased().contains(q) || CaptureLibrary.transcript(c).lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if let id = model.selectedCaptureID, let c = items.first(where: { $0.id == id }) {
                CaptureDetail(capture: c, back: { model.selectedCaptureID = nil }, deleted: { reload(); model.selectedCaptureID = nil })
            } else {
                list
            }
        }
        .background(DF.paper)
        .onAppear(perform: reload)
        .onChange(of: service.shelf) { _, _ in reload() }
    }

    private func reload() { items = service.all() }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Captures", subtitle: subtitle) {
                Button { CaptureService.shared.toggleRecording() } label: {
                    HStack(spacing: 7) {
                        Circle().fill(DF.now).frame(width: 7, height: 7)
                        Text("Record")
                    }
                }
                .buttonStyle(.df(.primary))
            }
            HStack(alignment: .bottom) {
                DFTabs(items: [(Filter.all, "All"), (.recordings, "Recordings"), (.screenshots, "Screenshots")], selection: $filter)
                Spacer()
                SearchField(text: $query, prompt: "Search captures").frame(width: 240).padding(.bottom, 6)
            }
            .padding(.horizontal, DF.inset)
            .overlay(alignment: .bottom) { Rectangle().fill(DF.line).frame(height: 1).padding(.horizontal, DF.inset) }

            if shown.isEmpty {
                EmptyState(title: items.isEmpty ? "Nothing captured yet" : "Nothing matches",
                           message: items.isEmpty ? "fn Space takes a screenshot. fn ⌘ records your screen with your face and voice."
                                                  : "Try another word, or another tab.")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        let (week, earlier) = split(shown)
                        if !week.isEmpty { grid(week) }
                        if !earlier.isEmpty {
                            Text("Earlier").font(DF.font(13, .medium)).foregroundStyle(DF.faint).padding(.top, 8)
                            grid(earlier)
                        }
                    }
                    .padding(.horizontal, DF.inset).padding(.top, 22).padding(.bottom, 32)
                }
            }
        }
    }

    private var subtitle: String {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? .distantPast
        let n = items.filter { $0.date >= weekStart }.count
        return "\(n) this week"
    }

    private func split(_ list: [Capture]) -> ([Capture], [Capture]) {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? .distantPast
        return (list.filter { $0.date >= weekStart }, list.filter { $0.date < weekStart })
    }

    private func grid(_ list: [Capture]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 18, alignment: .top)], alignment: .leading, spacing: 22) {
            ForEach(list) { c in
                CaptureTile(capture: c).onTapGesture { model.selectedCaptureID = c.id }
            }
        }
    }
}

/// One capture in the grid: its picture on a soft grey well, a title and when.
private struct CaptureTile: View {
    let capture: Capture
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // The well sets the size; the picture fills it without pushing the tile wider than its column.
            RoundedRectangle(cornerRadius: 8).fill(DF.canvas)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay { CapturePoster(capture: capture).padding(capture.kind == .shot ? 10 : 0) }
                .overlay(alignment: .bottomTrailing) {
                    if capture.kind == .recording, let d = CaptureLibrary.duration(capture) {
                        Text(CaptureLibrary.time(d)).font(DF.font(11, .medium)).foregroundStyle(DF.ink.opacity(0.75))
                            .padding(.horizontal, 6).frame(height: 18)
                            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.92)))
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hover ? DF.line.opacity(2.2) : DF.line))
            VStack(alignment: .leading, spacing: 2) {
                Text(CaptureLibrary.title(capture)).font(DF.font(14, .medium)).foregroundStyle(DF.ink).lineLimit(1)
                Text(CaptureLibrary.meta(capture)).font(DF.font(12)).foregroundStyle(DF.muted).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .dfContextMenu {
            [.action("Copy", icon: "doc.on.doc") { CaptureService.shared.copy(capture) },
             .action("Show in Finder", icon: "folder") { CaptureService.shared.reveal(capture) }]
        }
    }
}

// MARK: - Detail

private struct CaptureDetail: View {
    let capture: Capture
    let back: () -> Void
    let deleted: () -> Void
    @State private var polished = true
    @State private var copied = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Button(action: back) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Captures")
                    }
                    .font(DF.font(13, .medium)).foregroundStyle(DF.muted)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text(CaptureLibrary.title(capture)).font(DF.serif(32)).tracking(-0.6)
                    Text(CaptureLibrary.meta(capture)).font(DF.font(13)).foregroundStyle(DF.muted)
                }

                HStack(spacing: 8) {
                    if capture.kind == .recording && capture.polished != nil {
                        DFSegmented(items: [(false, "Raw"), (true, "Polished")], selection: $polished)
                    }
                    Spacer()
                    Button { CaptureService.shared.copy(capture, polished: polished); flashCopied() } label: {
                        Label(copied ? "Copied" : "Copy for your agent", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.df(.primary))
                    Button { CaptureService.shared.reveal(capture) } label: { Label("Show in Finder", systemImage: "folder") }
                        .buttonStyle(.df(.secondary))
                    Button { CaptureLibrary.trash(capture); deleted() } label: { Image(systemName: "trash") }
                        .buttonStyle(.df(.danger))
                        .help("Move to the Trash")
                }

                if capture.kind == .recording {
                    VideoBox(url: polished ? (capture.polished ?? capture.url) : capture.url)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .id(polished)
                } else if let img = NSImage(contentsOf: capture.url) {
                    Image(nsImage: img).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DF.line))
                }

                if capture.kind == .recording {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What was said").font(DF.font(14, .semibold))
                        let text = CaptureLibrary.transcript(capture)
                        Text(text.isEmpty ? "Nothing was said in this one." : text)
                            .font(DF.font(14)).foregroundStyle(text.isEmpty ? DF.muted : DF.ink.opacity(0.85))
                            .lineSpacing(3).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, DF.docInset).padding(.top, DF.pageTop + 8).padding(.bottom, 40)
            .frame(maxWidth: DF.docWidth, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private func flashCopied() {
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = false } }
    }
}

/// A video with Oatmeal's own controls: play/pause, a scrubber and the time (no system player UI).
private struct VideoBox: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var position = 0.0
    @State private var duration = 0.0
    @State private var observer: Any?

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10).fill(DF.canvas)
            if let player { PlayerLayerView(player: player) }
            HStack(spacing: 10) {
                Button { toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Circle().fill(Color.black.opacity(0.7)))
                }
                .buttonStyle(.plain)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.5)).frame(height: 4)
                        Capsule().fill(Color.white).frame(width: g.size.width * (duration > 0 ? position / duration : 0), height: 4)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        guard duration > 0 else { return }
                        let t = max(0, min(duration, Double(v.location.x / g.size.width) * duration))
                        position = t
                        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    })
                }
                .frame(height: 30)
                Text("\(CaptureLibrary.time(position)) / \(CaptureLibrary.time(duration))")
                    .font(DF.font(12, .medium)).monospacedDigit().foregroundStyle(.white)
                    .padding(.horizontal, 7).frame(height: 22).background(Capsule().fill(Color.black.opacity(0.55)))
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DF.line))
        .onAppear(perform: load)
        .onDisappear { player?.pause(); if let observer { player?.removeTimeObserver(observer) } }
    }

    private func load() {
        let p = AVPlayer(url: url)
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { t in
            MainActor.assumeIsolated {
                position = t.seconds
                if let d = p.currentItem?.duration.seconds, d.isFinite { duration = d }
                playing = p.rate > 0
            }
        }
        player = p
    }

    private func toggle() {
        guard let player else { return }
        if playing { player.pause() } else {
            if duration > 0, position >= duration - 0.05 { player.seek(to: .zero) }
            player.play()
        }
    }
}

private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        v.layer = layer
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { (v.layer as? AVPlayerLayer)?.player = player }
}

/// A capture's picture: the screenshot itself, or a frame from the middle of the recording (the polished one when
/// there is one).
struct CapturePoster: View {
    let capture: Capture
    var polished = true
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: capture.kind == .shot ? .fit : .fill)
            } else {
                Color.clear
            }
        }
        .task(id: "\(capture.id)\(polished)\(capture.polished?.path ?? "")") { image = await CaptureLibrary.poster(capture, polished: polished) }
    }
}

/// Small shared helpers for captures: titles, times, posters, transcripts, the Trash.
@MainActor
enum CaptureLibrary {
    private static var posters: [String: NSImage] = [:]
    private static var durations: [String: Double] = [:]

    static func title(_ c: Capture) -> String {
        if let t = c.title, !t.isEmpty { return t }
        return c.kind == .shot ? "Screenshot" : "Screen recording"
    }

    static func meta(_ c: Capture) -> String {
        let when: String
        if Calendar.current.isDateInToday(c.date) { when = "Today " + c.date.formatted(date: .omitted, time: .shortened).lowercased() }
        else if Calendar.current.isDateInYesterday(c.date) { when = "Yesterday" }
        else { when = c.date.formatted(.dateTime.month(.abbreviated).day()) }
        return (c.kind == .shot ? "Screenshot" : "Recording") + " · " + when
    }

    static func time(_ s: Double) -> String {
        let n = Int(s.isFinite ? s : 0)
        return String(format: "%d:%02d", n / 60, n % 60)
    }

    static func duration(_ c: Capture) -> Double? {
        if let d = durations[c.id] { return d }
        guard c.kind == .recording else { return nil }
        let base = c.url.deletingPathExtension().lastPathComponent
        let meta = c.url.deletingLastPathComponent().appendingPathComponent(base + ".json")
        if let data = try? Data(contentsOf: meta), let m = try? JSONDecoder().decode(CapturePolish.Meta.self, from: data) {
            durations[c.id] = m.duration
            return m.duration
        }
        return nil
    }

    static func transcript(_ c: Capture) -> String {
        guard let url = c.transcript else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func poster(_ c: Capture, polished: Bool) async -> NSImage? {
        let url = c.kind == .shot ? c.url : (polished ? (c.polished ?? c.url) : c.url)
        let key = url.path
        if let p = posters[key] { return p }
        let image: NSImage?
        if c.kind == .shot {
            image = await Task.detached { () -> NSImage? in
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 900] as CFDictionary)
                else { return nil }
                return NSImage(cgImage: cg, size: .zero)
            }.value
        } else {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let asset = AVURLAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.maximumSize = CGSize(width: 900, height: 900)
            gen.appliesPreferredTrackTransform = true
            let d = (try? await asset.load(.duration).seconds) ?? 0
            if let (cg, _) = try? await gen.image(at: CMTime(seconds: max(0, d * 0.45), preferredTimescale: 600)) {
                image = NSImage(cgImage: cg, size: .zero)
            } else { image = nil }
        }
        if let image { posters[key] = image }
        return image
    }

    /// Moves a capture and everything made from it (polished video, frames, transcript, title, project) to the Trash.
    static func trash(_ c: Capture) {
        let dir = c.url.deletingLastPathComponent(), base = c.url.deletingPathExtension().lastPathComponent
        var urls = [c.url, c.polished, c.frames, c.transcript].compactMap { $0 }
        urls.append(dir.appendingPathComponent(base + ".json"))
        urls.append(CapturePolish.projects.appendingPathComponent(base + ".lurker"))
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        NSWorkspace.shared.recycle(existing)
        CaptureService.shared.remove(c)
    }
}

import AVFoundation
import AppKit
import LurkerCore
import LurkerEngine

/// Turns a finished take into what lands on the shelf, with Lurker's engine:
///   capture-<stamp>.mp4            raw: the recording as it was, with your camera bubble where it sat on screen
///   capture-<stamp>.polished.mp4   polished: zooms on clicks and typing, a soft frame, your camera in the corner
///   capture-<stamp>.txt            what was said, transcribed on this Mac
///   capture-<stamp>.json           its title
/// The Lurker project itself stays in Application Support, so it can be opened again for Edit.
enum CapturePolish {
    static var projects: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Oatmeal/Recordings", isDirectory: true)
    }

    struct Camera {
        let url: URL
        /// Take seconds at which the camera file starts.
        let offset: Double
        /// The bubble and what was recorded, global top-left points.
        let bubble: CGRect?
        let target: CGRect
    }

    struct Meta: Codable { var title: String; var duration: Double }

    @MainActor
    static func finish(bundle: ProjectBundle, manifest: TakeManifest, camera: Camera?, stamp: String) async {
        let folder = CaptureService.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let raw = folder.appendingPathComponent("capture-\(stamp).mp4")
        let polished = folder.appendingPathComponent("capture-\(stamp).polished.mp4")
        var c = Capture(url: raw, kind: .recording, date: Date())
        c.status = "Saving"; c.progress = 0
        let service = CaptureService.shared
        service.startFinishing(c)
        func update(_ change: @escaping (inout Capture) -> Void) { service.updateFinishing(id: c.id, change) }

        do {
            guard manifest.status == .finished, manifest.duration > 0.5 else {
                throw EngineError(manifest.warnings.first ?? "The recording was too short.")
            }
            var m = manifest
            let dir = bundle.takeDirectory("t1")
            try await mixAudio(in: dir, manifest: &m)
            if let camera { try writeCameraInfo(camera, to: dir) }

            var doc = try ProjectBundle.open(bundle.url).1
            try doc.addRecording(m)
            try bundle.save(doc)

            // Raw: no frame, no zooms, no ripple; the camera stays where it was.
            var plain = doc.project
            plain.canvas.padding = 0
            plain.canvas.radius = 0
            plain.canvas.inset = 0
            var noShadow = Canvas.Shadow(); noShadow.opacity = 0
            plain.canvas.shadow = noShadow
            plain.cursor.click = CursorStyle.Click.none
            try await export(bundle, project: plain, to: raw) { p in update { $0.progress = p * 0.35 } }
            let frames = await CaptureService.contactSheet(for: raw)
            update { $0.frames = frames; $0.status = "Polishing" }

            // Polished: Lurker's auto edit, a soft Notion-grey frame, the camera in the corner.
            _ = try await AutoEdit.apply(bundle, take: "t1")
            var look = try ProjectBundle.open(bundle.url).1.project
            look.canvas.padding = 0.06
            look.canvas.radius = 14
            look.canvas.background = .object(["type": .string("gradient"), "colors": .array([.string("#F7F7F5"), .string("#E9E8E4")])])
            try await export(bundle, project: look, to: polished) { p in update { $0.progress = 0.35 + p * 0.5 } }
            update { $0.polished = polished; $0.status = "Writing the transcript"; $0.progress = 0.88 }

            // What was said, for your agent (and the title).
            let asset = AVURLAsset(url: raw)
            let text: String
            if (try? await asset.loadTracks(withMediaType: .audio).first) != nil {
                let segments = (try? await AudioImporter.transcribe(asset, duration: m.duration) { _ in }) ?? []
                text = segments.map(\.text).joined(separator: " ")
            } else { text = "" }
            let transcript = folder.appendingPathComponent("capture-\(stamp).txt")
            if !text.isEmpty { try? text.write(to: transcript, atomically: true, encoding: .utf8) }
            let title = Self.title(from: text, manifest: m)
            if let data = try? JSONEncoder().encode(Meta(title: title, duration: m.duration)) {
                try? data.write(to: folder.appendingPathComponent("capture-\(stamp).json"))
            }
            update {
                $0.transcript = text.isEmpty ? nil : transcript
                $0.title = title
                $0.status = nil; $0.progress = nil
            }
            DFLog.log("recorder", "finished \(raw.lastPathComponent)")
        } catch {
            DFLog.log("recorder", "finishing failed: \(error)")
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            update { $0.status = "Couldn't finish: \(message)"; $0.progress = nil }
        }
    }

    /// Exports off the main actor (the engine renders synchronously on the GPU).
    private static func export(_ bundle: ProjectBundle, project: Project, to url: URL, progress: @escaping @MainActor (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        try await Task.detached(priority: .userInitiated) {
            _ = try await Exporter().export(bundle: bundle, project: project, preset: ExportPreset.named(.web), to: url) { p in
                Task { @MainActor in progress(p) }
            }
        }.value
    }

    /// The engine hears one audio track (system.mov): mix the Mac's sound and the mic into it.
    private static func mixAudio(in dir: URL, manifest m: inout TakeManifest) async throws {
        let fm = FileManager.default
        let system = dir.appending(path: "system.mov"), mic = dir.appending(path: "mic.mov")
        let hasSystem = fm.fileExists(atPath: system.path), hasMic = fm.fileExists(atPath: mic.path)
        guard hasMic else { return }
        if !hasSystem {
            try fm.copyItem(at: mic, to: system)
        } else {
            let mixed = dir.appending(path: "mixed.mov")
            try await mix([system, mic], to: mixed)
            try fm.moveItem(at: system, to: dir.appending(path: "system-only.mov"))
            try fm.moveItem(at: mixed, to: system)
        }
        if !m.tracks.contains(where: { $0.kind == "system" }) {
            m.tracks.append(.init(kind: "system", file: "system.mov"))
        }
        try m.save(to: dir)
    }

    /// Every audio track of `inputs`, from time zero, mixed into one AAC track.
    private static func mix(_ inputs: [URL], to out: URL) async throws {
        let comp = AVMutableComposition()
        for url in inputs {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try await asset.load(.duration)
            let t = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try t?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        }
        let tracks = try await comp.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: comp)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        try? FileManager.default.removeItem(at: out)
        let writer = try AVAssetWriter(outputURL: out, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000,
        ])
        writer.add(input)
        guard reader.startReading(), writer.startWriting() else { throw reader.error ?? writer.error ?? EngineError("couldn't mix the audio") }
        writer.startSession(atSourceTime: .zero)
        while let sb = output.copyNextSampleBuffer() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            input.append(sb)
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? EngineError("couldn't mix the audio") }
    }

    private static func writeCameraInfo(_ c: Camera, to dir: URL) throws {
        let t = c.target
        var x = 0.12, y = 0.82, size = 0.2
        if let b = c.bubble, t.width > 0, t.height > 0 {
            size = min(0.32, max(0.12, Double(b.height / t.height)))
            let cx = Double((b.midX - t.minX) / t.width), cy = Double((b.midY - t.minY) / t.height)
            // a bubble outside what was recorded goes to its bottom-left corner
            if (0...1).contains(cx) && (0...1).contains(cy) { x = cx; y = cy }
        }
        let info = Renderer.CameraInfo(offset: c.offset, x: x, y: y, size: size, mirror: true)
        try JSONEncoder().encode(info).write(to: dir.appending(path: "camera.json"))
    }

    /// The first few words of what was said, else the app or "Screen recording".
    static func title(from text: String, manifest: TakeManifest) -> String {
        let firstSentence = text.split(whereSeparator: { ".?!".contains($0) }).first.map(String.init) ?? ""
        let words = firstSentence.split(separator: " ").prefix(7)
        if words.count >= 3 {
            var s = words.joined(separator: " ")
            if let f = s.first { s.replaceSubrange(s.startIndex...s.startIndex, with: String(f).uppercased()) }
            return s
        }
        if let app = manifest.source.app, !app.isEmpty { return "Recording of \(app)" }
        return "Screen recording"
    }
}

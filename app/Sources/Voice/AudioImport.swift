import AppKit
import AVFoundation
import FluidAudio
import SwiftData
import UniformTypeIdentifiers

/// Meetings › Import: turn an audio or video file (a voice memo, a Zoom recording, a podcast clip) into
/// a meeting with a transcript, using the same on-device speech model as dictation. Long files are cut
/// into ~30 s pieces at quiet moments so words aren't split.
@MainActor
final class AudioImporter: ObservableObject {
    static let shared = AudioImporter()

    struct Job: Equatable {
        var name: String
        var progress: Double
        var error: String?
    }
    @Published private(set) var job: Job?

    var busy: Bool { job != nil && job?.error == nil }

    func pickAndImport() {
        let panel = NSOpenPanel()
        panel.title = "Transcribe a recording"
        panel.prompt = "Transcribe"
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .quickTimeMovie, .mpeg4Audio, .mp3, .wav, .aiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importFile(url) }
    }

    func dismissError() { job = nil }

    /// Rebuilds a meeting for every recording in Oatmeal/Meetings that has none, oldest first. For when
    /// the database is lost but the audio isn't (Oct 31: icloudmailagent replaced the shared store).
    func rebuildFromRecordings() async {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: MeetingService.meetingsDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "m4a" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let have = ((try? AppModel.shared.context.fetch(FetchDescriptor<MeetingNote>())) ?? []).map(\.startedAt)
        var rebuilt = 0, skipped = 0
        for file in files {
            guard let start = Self.recordingStart(file) else { continue }
            // Already a meeting within 3 minutes of this recording's start: it's that one.
            if have.contains(where: { abs($0.timeIntervalSince(start)) < 180 }) { skipped += 1; continue }
            await importFile(file, startedAt: start, title: "Meeting")
            if let error = job?.error { DFLog.log("rebuild", "\(file.lastPathComponent): \(error)"); job = nil } else { rebuilt += 1 }
        }
        DFLog.log("rebuild", "rebuilt \(rebuilt) meeting(s) from \(files.count) recordings; \(skipped) already had one")
    }

    /// "2026-10-22-110714.m4a" → 22 Oct 2026, 11:07:14 local time (when recording started).
    nonisolated static func recordingStart(_ file: URL) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.date(from: file.deletingPathExtension().lastPathComponent)
    }

    func importFile(_ url: URL, startedAt: Date? = nil, title: String? = nil) async {
        guard !busy else { return }
        let name = title ?? url.deletingPathExtension().lastPathComponent
        job = Job(name: name, progress: 0)
        do {
            await DictationService.shared.prepareModel()
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw ImportError.noAudio }
            let segments = try await Self.transcribe(asset, duration: duration) { p in
                Task { @MainActor in AudioImporter.shared.job?.progress = p }
            }
            guard !segments.isEmpty else { throw ImportError.noSpeech }

            let created = startedAt ?? (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            let note = MeetingNote(title: name, startedAt: created)
            note.duration = duration
            note.transcriptData = (try? JSONEncoder().encode(segments)) ?? Data()
            job?.progress = 1
            let ctx = AppModel.shared.context
            ctx.insert(note)
            try? ctx.save()
            AppModel.shared.selectedMeetingID = note.id
            NoteWriters.shared.meetingSaved(note)
            job = nil
        } catch {
            job?.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    enum ImportError: LocalizedError {
        case noAudio, noSpeech, unreadable
        var errorDescription: String? {
            switch self {
            case .noAudio: "That file has no audio track."
            case .noSpeech: "No speech was found in that file."
            case .unreadable: "Couldn\u{2019}t read that file."
            }
        }
    }

    // MARK: Decoding and transcription

    nonisolated private static let rate = 16_000.0
    nonisolated private static let target = 30.0     // seconds per piece
    nonisolated private static let slack = 4.0       // look this far back for a quiet place to cut

    /// Streams the file as 16 kHz mono Float32 (AVAssetReader does the resampling), transcribing as it goes.
    nonisolated private static func transcribe(_ asset: AVURLAsset, duration: Double,
                                               progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw ImportError.noAudio }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ImportError.unreadable }

        var pending: [Float] = []
        var consumed = 0.0          // seconds already transcribed
        var segments: [TranscriptSegment] = []

        func flush(_ samples: [Float], at offset: Double) async throws {
            guard AudioSamples.hasEnergy(samples, threshold: 0.002) else { return }
            let text = try await SpeechEngine.shared.transcribe(samples, source: .system)
            if !text.isEmpty { segments.append(TranscriptSegment(speaker: "Speaker", text: text, offset: offset)) }
        }

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            pending.append(contentsOf: floats(buffer))
            while Double(pending.count) >= (target + slack) * rate {
                let cut = quietCut(in: pending)
                try await flush(Array(pending[..<cut]), at: consumed)
                consumed += Double(cut) / rate
                pending.removeFirst(cut)
                progress(min(0.99, consumed / duration))
            }
        }
        if reader.status == .failed { throw reader.error ?? ImportError.unreadable }
        if !pending.isEmpty { try await flush(pending, at: consumed) }
        progress(1)
        return segments
    }

    /// Index to cut at: the quietest 100 ms between (target - slack) and target seconds.
    nonisolated private static func quietCut(in samples: [Float]) -> Int {
        let window = Int(rate * 0.1)
        let start = Int((target - slack) * rate), end = min(samples.count - window, Int(target * rate))
        guard start < end else { return min(samples.count, Int(target * rate)) }
        var best = end, bestEnergy = Float.greatestFiniteMagnitude
        var i = start
        while i < end {
            let e = AudioSamples.rms(samples[i..<(i + window)])
            if e < bestEnergy { bestEnergy = e; best = i + window / 2 }
            i += window / 2
        }
        return best
    }

    nonisolated private static func floats(_ buffer: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return [] }
        let length = CMBlockBufferGetDataLength(block)
        var out = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        out.withUnsafeMutableBytes { raw in
            _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
        }
        return out
    }
}

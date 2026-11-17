import AVFoundation
import LurkerCore

/// The program's sound: each take's system audio cut and stretched exactly like the picture, with the volume and the
/// sped-up stretches' ducking. It's rendered offline into one file (`ProgramAudio`), and the composition plays that
/// file from start to end, so the editor's preview and every export hear the same samples.
public struct AudioTimeline {
    let composition: AVMutableComposition
    let hasAudio: Bool

    static let timescale: CMTimeScale = 48_000

    static func build(_ project: Project, map: TimeMap, bundle: ProjectBundle) async throws -> AudioTimeline {
        let comp = AVMutableComposition()
        // source tracks per take, loaded once
        var sources: [String: ProgramAudio.Source] = [:]
        for (id, take) in project.takes where (take.tracks ?? []).contains("system") {
            let url = bundle.takeDirectory(id).appending(path: "system.mov")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            guard let t = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let stamp = "\((attrs[.size] as? Int) ?? 0) \((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
            sources[id] = .init(asset: asset, track: t, stamp: stamp)
        }
        let dir = bundle.derivedDirectory.appending(path: "audio", directoryHint: .isDirectory)
        guard let (url, frames) = try await ProgramAudio.file(project, map: map, sources: sources, dir: dir),
              let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return AudioTimeline(composition: comp, hasAudio: false)
        }
        // tracks only hold their asset weakly: keep it alive while inserting
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let t = try await asset.loadTracks(withMediaType: .audio).first else { throw EngineError("no sound in \(url.lastPathComponent)") }
        try withExtendedLifetime(asset) {
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(value: Int64(frames), timescale: timescale)), of: t, at: .zero)
        }
        return AudioTimeline(composition: comp, hasAudio: true)
    }
}

extension AudioTimeline {
    /// The composition for live playback (the editor), or nil when the program is silent.
    public static func preview(_ project: Project, map: TimeMap, bundle: ProjectBundle) async throws -> AVComposition? {
        let t = try await build(project, map: map, bundle: bundle)
        return t.hasAudio ? t.composition.copy() as? AVComposition : nil
    }
}

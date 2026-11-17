import Foundation
import LurkerCore

/// Plans and applies automatic edits for a project's takes (one undoable change).
public enum AutoEdit {
    public static func plan(_ bundle: ProjectBundle, project: Project, take: String, options: Planner.Options) async throws -> Planner.Plan {
        guard let info = project.takes[take] else { throw EngineError("no take \(take)") }
        let dir = bundle.takeDirectory(take)
        let screen = dir.appending(path: "screen.mov")
        let size = CGSize(width: info.width ?? 1920, height: info.height ?? 1080)
        let events = EventTrack.load(dir.appending(path: "events.jsonl"), sourceSize: size)
        var crop = CGRect(origin: .zero, size: size)
        if (try? TakeManifest.load(dir))?.source.kind == "window", !(project.canvas.titleBar ?? false), FileManager.default.fileExists(atPath: screen.path) {
            let cut = await WindowChrome.frame(screen, at: min(1, info.duration / 2)).map { WindowChrome.titleBarHeight($0, scale: events.scale) } ?? 0
            if cut > 0 && Double(cut) < size.height / 3 { crop = CGRect(x: 0, y: Double(cut), width: size.width, height: size.height - Double(cut)) }
        }
        let frames = options.idle && FileManager.default.fileExists(atPath: screen.path) ? try await FrameActivity.read(screen) : nil
        return Planner.plan(take: take, events: events, duration: info.duration, crop: crop, frames: frames, options: options)
    }

    /// Re-plans every take (or one) and swaps in the results; manual regions stay as they are.
    public static func apply(_ bundle: ProjectBundle, take: String? = nil, options: Planner.Options = .init()) async throws -> (EditResult, [String]) {
        var (_, doc) = try ProjectBundle.open(bundle.url)
        let takes = take.map { [$0] } ?? doc.project.takes.keys.sorted()
        var notes: [String] = []
        var last = EditResult(rev: doc.project.rev, label: "auto edit")
        var created: [String] = []
        for id in takes {
            let plan = try await plan(bundle, project: doc.project, take: id, options: options)
            notes += plan.notes.map { "\(id): \($0)" }
            last = try doc.replaceAutoRegions(take: id, zooms: options.zooms ? plan.zooms : nil, speeds: options.typing || options.idle ? plan.speeds : nil,
                                              label: "auto edit \(id)")
            created += last.created
        }
        try bundle.save(doc)
        last.created = created
        try bundle.log(EditBatch(ops: [.note(.init(text: "auto edit: " + notes.joined(separator: "; ")))], label: last.label), last)
        return (last, notes)
    }
}

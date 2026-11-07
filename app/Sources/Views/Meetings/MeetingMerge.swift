import Foundation
import SwiftData

/// Joins meetings that are really one (a call that dropped, a recording stopped too early).
@MainActor
enum MeetingMerge {
    /// Merges into the earliest meeting, in time order, and deletes the others. Each part's transcript
    /// follows on from the end of the one before, so the timestamps keep counting up.
    @discardableResult
    static func merge(_ notes: [MeetingNote], in ctx: ModelContext) -> MeetingNote? {
        let parts = notes.sorted { $0.startedAt < $1.startedAt }
        guard let base = parts.first, parts.count > 1 else { return parts.first }

        var segments: [TranscriptSegment] = []
        var elapsed: Double = 0
        for p in parts {
            let segs = (try? JSONDecoder().decode([TranscriptSegment].self, from: p.transcriptData)) ?? []
            segments += segs.map { TranscriptSegment(id: $0.id, speaker: $0.speaker, text: $0.text, offset: $0.offset + elapsed) }
            elapsed += max(p.duration, segs.last?.offset ?? 0)
        }

        // Label each part's own notes with its title once there's more than one to tell apart.
        func joined(_ text: (MeetingNote) -> String, heading: (MeetingNote) -> String) -> String {
            let filled = parts.filter { !text($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if filled.count < 2 { return filled.first.map(text) ?? "" }
            return filled.map { heading($0) + text($0) }.joined(separator: "\n\n")
        }
        let time: (MeetingNote) -> String = { $0.startedAt.formatted(date: .omitted, time: .shortened) }

        base.title = parts.first { !isGeneric($0.title) }?.title ?? base.title
        base.transcriptData = (try? JSONEncoder().encode(segments)) ?? Data()
        base.duration = elapsed
        base.myNotes = joined({ $0.myNotes }, heading: { "\($0.title) (\(time($0)))\n" })
        base.notesMarkdown = joined({ $0.notesMarkdown }, heading: { _ in "" })
        base.summary = parts.flatMap(\.summary)
        base.actionItems = parts.flatMap(\.actionItems)
        base.addedItems = parts.flatMap(\.addedItems)
        base.attendees = parts.flatMap(\.attendees).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        base.calendarEventID = base.calendarEventID ?? parts.lazy.compactMap(\.calendarEventID).first
        base.folderID = base.folderID ?? parts.lazy.compactMap(\.folderID).first

        for p in parts.dropFirst() { ctx.delete(p) }
        try? ctx.save()
        return base
    }

    /// The default "Meeting" title is worth replacing with a real one from another part.
    private static func isGeneric(_ title: String) -> Bool {
        let t = title.lowercased().trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t == "meeting"
    }
}

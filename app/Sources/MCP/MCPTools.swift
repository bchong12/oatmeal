import Foundation
import SwiftData

/// A tool failure that goes back to the client as `isError: true`.
struct MCPToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// The Oatmeal tools exposed over MCP. Everything runs on the main actor against
/// `AppModel.shared.context`, and writes are saved straight away so the UI updates.
@MainActor
struct MCPTools {
    var context: ModelContext { AppModel.shared.context }
    private var cal: Calendar { .oatmeal }

    static var names: [String] { definitions.compactMap { $0["name"] as? String } }

    func call(_ name: String, _ args: [String: Any]) -> [String: Any] {
        do {
            let value: Any
            switch name {
            case "list_meetings": value = try listMeetings(args)
            case "get_meeting": value = try getMeeting(args)
            case "update_meeting": value = try updateMeeting(args)
            case "search_dictations": value = try searchDictations(args)
            default: throw MCPToolError("Unknown tool: \(name)")
            }
            return ["content": [["type": "text", "text": Self.pretty(value)]], "isError": false]
        } catch let e as MCPToolError {
            return ["content": [["type": "text", "text": e.message]], "isError": true]
        } catch {
            return ["content": [["type": "text", "text": "Oatmeal error: \(error.localizedDescription)"]], "isError": true]
        }
    }

    // MARK: Meetings and dictation

    private func listMeetings(_ args: [String: Any]) throws -> Any {
        let limit = max(1, min(Self.int(args["limit"]) ?? 20, 200))
        let query = (args["query"] as? String)?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        var notes = try context.fetch(FetchDescriptor<MeetingNote>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
        if !query.isEmpty {
            notes = notes.filter { n in
                n.title.lowercased().contains(query) || n.myNotes.lowercased().contains(query)
                    || n.summary.contains { $0.lowercased().contains(query) }
                    || n.actionItems.contains { $0.lowercased().contains(query) }
                    || n.attendees.contains { $0.lowercased().contains(query) }
                    || transcriptText(n).lowercased().contains(query)
            }
        }
        let items: [[String: Any]] = notes.prefix(limit).map { n in
            ["id": n.id.uuidString, "title": n.title, "started_at": Self.isoString(n.startedAt),
             "duration_minutes": Int((n.duration / 60).rounded()), "attendees": n.attendees,
             "summary": n.summary, "action_item_count": n.actionItems.count, "folder": folderName(n) ?? NSNull()]
        }
        return ["count": items.count, "meetings": items] as [String: Any]
    }

    private func getMeeting(_ args: [String: Any]) throws -> Any {
        guard let raw = args["id"] as? String, let id = UUID(uuidString: raw) else { throw MCPToolError("`id` must be a meeting id from list_meetings.") }
        let notes = try context.fetch(FetchDescriptor<MeetingNote>(predicate: #Predicate { $0.id == id }))
        guard let n = notes.first else { throw MCPToolError("No meeting with id \(raw).") }
        return [
            "id": n.id.uuidString, "title": n.title, "started_at": Self.isoString(n.startedAt),
            "duration_minutes": Int((n.duration / 60).rounded()), "attendees": n.attendees,
            "summary": n.summary, "action_items": n.actionItems, "added_to_board": n.addedItems,
            "my_notes": n.myNotes, "notes": n.notesMarkdown, "folder": folderName(n) ?? NSNull(), "transcript": transcriptText(n, numbered: true),
        ] as [String: Any]
    }

    /// Writes an agent's cleaned-up meeting back: title, summary, action items, attendees and fixes to
    /// individual transcript lines. The user's own typed notes are never touched. Everything is validated
    /// before anything is changed, so a bad index leaves the meeting as it was.
    private func updateMeeting(_ args: [String: Any]) throws -> Any {
        guard let raw = args["id"] as? String, let id = UUID(uuidString: raw) else { throw MCPToolError("`id` must be a meeting id from list_meetings.") }
        guard let n = try context.fetch(FetchDescriptor<MeetingNote>(predicate: #Predicate { $0.id == id })).first else { throw MCPToolError("No meeting with id \(raw).") }

        func strings(_ key: String) throws -> [String]? {
            guard let v = args[key] else { return nil }
            guard let arr = v as? [Any] else { throw MCPToolError("`\(key)` must be an array of strings.") }
            return arr.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        func text(_ v: Any?, _ what: String) throws -> String {
            guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { throw MCPToolError("\(what) must be a non-empty string.") }
            return s
        }
        let summary = try strings("summary"), actionItems = try strings("action_items"), attendees = try strings("attendees")
        let title = try args["title"].map { try text($0, "`title`") }
        let notes = try args["notes"].map { try text($0, "`notes`") }
        // "" removes it from its folder; a new name makes the folder.
        var folder: (set: Bool, name: String) = (false, "")
        if let f = args["folder"] {
            guard let s = f as? String else { throw MCPToolError("`folder` must be a folder name, or \"\" to remove it from its folder.") }
            folder = (true, s.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var segments: [TranscriptSegment]?
        var edited = 0
        if let rawEdits = args["transcript_edits"] {
            guard let edits = rawEdits as? [[String: Any]] else { throw MCPToolError("`transcript_edits` must be an array of {index, text?, speaker?}.") }
            guard var segs = try? JSONDecoder().decode([TranscriptSegment].self, from: n.transcriptData), !segs.isEmpty else {
                throw MCPToolError("This meeting has no transcript to edit.")
            }
            for e in edits {
                guard let i = Self.int(e["index"]), segs.indices.contains(i) else {
                    throw MCPToolError("transcript_edits index \(e["index"].map { "\($0)" } ?? "missing") is out of range (0...\(segs.count - 1)); use the #numbers from get_meeting.")
                }
                if e["text"] == nil && e["speaker"] == nil { throw MCPToolError("transcript_edits entry \(i) needs `text` and/or `speaker`.") }
                if let t = e["text"] { segs[i].text = try text(t, "transcript_edits text") }
                if let sp = e["speaker"] { segs[i].speaker = try text(sp, "transcript_edits speaker") }
                edited += 1
            }
            segments = segs
        }
        if title == nil, notes == nil, summary == nil, actionItems == nil, attendees == nil, segments == nil, !folder.set {
            throw MCPToolError("Nothing to update: pass title, notes, summary, action_items, attendees and/or transcript_edits.")
        }

        if let title { n.title = title }
        if let notes { n.notesMarkdown = notes }
        if folder.set { n.folderID = folder.name.isEmpty ? nil : MeetingFolders.named(folder.name, in: context)?.id }
        if let summary { n.summary = summary }
        if let actionItems { n.actionItems = actionItems }
        if let attendees { n.attendees = attendees }
        if let segments { n.transcriptData = try JSONEncoder().encode(segments) }
        try context.save()
        return ["id": n.id.uuidString, "title": n.title, "summary_points": n.summary.count, "action_items": n.actionItems.count,
                "attendees": n.attendees, "notes_sections": n.notesMarkdown.split(separator: "\n").filter { $0.hasPrefix("#") }.count, "folder": folderName(n) ?? NSNull(),
                "transcript_lines_edited": edited] as [String: Any]
    }

    private func folderName(_ n: MeetingNote) -> String? {
        guard let id = n.folderID else { return nil }
        return try? context.fetch(FetchDescriptor<MeetingFolder>(predicate: #Predicate { $0.id == id })).first?.name
    }

    private func searchDictations(_ args: [String: Any]) throws -> Any {
        guard let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespaces), !query.isEmpty else {
            throw MCPToolError("`query` is required.")
        }
        let limit = max(1, min(Self.int(args["limit"]) ?? 20, 200))
        let q = query.lowercased()
        let entries = try context.fetch(FetchDescriptor<DictationEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            .filter { $0.text.lowercased().contains(q) || $0.appName.lowercased().contains(q) }
        let items: [[String: Any]] = entries.prefix(limit).map { e in
            ["id": e.id.uuidString, "text": e.text, "created_at": Self.isoString(e.createdAt),
             "destination": e.destination, "app": e.appName, "words": e.wordCount]
        }
        return ["query": query, "count": items.count, "total_matches": entries.count, "dictations": items] as [String: Any]
    }

    // MARK: Lookups

    private func transcriptText(_ n: MeetingNote, numbered: Bool = false) -> String {
        guard !n.transcriptData.isEmpty else { return "" }
        if let segs = try? JSONDecoder().decode([TranscriptSegment].self, from: n.transcriptData) {
            return segs.enumerated().map { i, seg in
                let s = Int(seg.offset)
                let stamp = String(format: "%02d:%02d", s / 60, s % 60)
                return "[\(numbered ? "#\(i) " : "")\(stamp)] \(seg.speaker): \(seg.text)"
            }.joined(separator: "\n")
        }
        return String(decoding: n.transcriptData, as: UTF8.self)
    }

    // MARK: JSON shapes

    // MARK: Parsing and formatting

    private func parseDay(_ value: Any?) throws -> Date? {
        guard let raw = (value as? String)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let today = cal.startOfDay(for: Date())
        switch raw.lowercased() {
        case "today": return today
        case "tomorrow": return cal.date(byAdding: .day, value: 1, to: today)
        case "yesterday": return cal.date(byAdding: .day, value: -1, to: today)
        default: break
        }
        let parts = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let d = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            throw MCPToolError("Dates are yyyy-MM-dd (or today/tomorrow), got \"\(raw)\".")
        }
        return cal.startOfDay(for: d)
    }

    static func weekday(from name: String) -> Int? {
        let s = name.lowercased().trimmingCharacters(in: .whitespaces)
        let table: [(String, Int)] = [("sun", 1), ("mon", 2), ("tue", 3), ("wed", 4), ("thu", 5), ("fri", 6), ("sat", 7)]
        return table.first { s.hasPrefix($0.0) }?.1
    }

    static func weekdayNames(_ days: [Int]) -> [String] {
        let names = [2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat", 1: "Sun"]
        return [2, 3, 4, 5, 6, 7, 1].filter(days.contains).compactMap { names[$0] }
    }

    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    static func dayString(_ d: Date) -> String {
        let c = Calendar.oatmeal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func timeString(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    static func isoString(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    static func pretty(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return "\(value)" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Tool definitions

extension MCPTools {
    private static let dateProp: [String: Any] = ["type": "string", "description": "Local date as yyyy-MM-dd, or today / tomorrow / yesterday."]
    private static let empty: [String: Any] = ["type": "object", "properties": [String: Any]()]

    static let definitions: [[String: Any]] = [
        [
            "name": "list_meetings",
            "description": "Recorded meetings, newest first, with id, title, start, duration, attendees and summary. `query` filters on title, notes, summary, action items, attendees and transcript.",
            "inputSchema": ["type": "object", "properties": [
                "limit": ["type": "integer", "description": "Max results (default 20)."],
                "query": ["type": "string"],
            ]],
        ],
        [
            "name": "get_meeting",
            "description": "One meeting in full: title, date, attendees, summary, action items, the user's own notes and the timestamped transcript (You = the user, Them = the call). Each transcript line is numbered, e.g. [#12 03:20], for update_meeting's transcript_edits.",
            "inputSchema": ["type": "object", "properties": ["id": ["type": "string", "description": "Meeting id from list_meetings."]], "required": ["id"]],
        ],
        [
            "name": "search_dictations",
            "description": "Search what the user has dictated with Oatmeal Flow, newest first.",
            "inputSchema": ["type": "object", "properties": [
                "query": ["type": "string", "description": "Text to look for (case-insensitive)."],
                "limit": ["type": "integer", "description": "Max results (default 20)."],
            ], "required": ["query"]],
        ],
        [
            "name": "update_meeting",
            "description": "Save a cleaned-up meeting: a better title, Granola-style notes, a short summary, action items, attendees, and fixes to individual transcript lines (mis-heard words, names, speaker labels). Pass only what you are changing; notes, summary, action_items and attendees REPLACE what is there. Transcript lines are addressed by the #index from get_meeting. The user's own typed notes are never changed. Read the meeting with get_meeting first and do not invent anything that was not said.",
            "inputSchema": ["type": "object", "properties": [
                "id": ["type": "string", "description": "Meeting id from list_meetings."],
                "title": ["type": "string", "description": "Short and specific, 2-6 words, e.g. \"Q4 launch plan with Sam\"."],
                "notes": ["type": "string", "description": "The meeting notes, Granola style, as markdown: 2-6 topic sections in meeting order, each `### Short topic` followed by 2-6 terse `- ` bullets (fragments, not sentences; keep names, numbers, dates and decisions exact; `  - ` for a detail under a bullet). Build them around the user's own notes. No action items here."],
                "summary": ["type": "array", "items": ["type": "string"], "description": "1-3 short lines giving the gist."],
                "action_items": ["type": "array", "items": ["type": "string"], "description": "One clear task each, with the owner and date if they were said, e.g. \"Send the revised quote by Friday (Sam)\"."],
                "attendees": ["type": "array", "items": ["type": "string"]],
                "folder": ["type": "string", "description": "File the meeting in this folder (made if it doesn't exist); \"\" removes it from its folder."],
                "transcript_edits": ["type": "array", "description": "Fixes to transcript lines.", "items": ["type": "object", "properties": [
                    "index": ["type": "integer", "description": "The #number of the line in get_meeting's transcript."],
                    "text": ["type": "string", "description": "The corrected line."],
                    "speaker": ["type": "string", "description": "A corrected speaker label."],
                ], "required": ["index"]]],
            ], "required": ["id"]],
        ],
    ]
}

import Foundation
import SwiftData

@Model
final class MeetingNote {
    var id: UUID = UUID()
    var title: String = ""
    var startedAt: Date = Date()
    var duration: Double = 0
    var transcriptData: Data = Data()
    var summary: [String] = []
    var actionItems: [String] = []
    var addedItems: [String] = []
    var calendarEventID: String?
    /// What you typed yourself during the meeting.
    var myNotes: String = ""
    /// Granola-style notes as light markdown: `### Topic` headings with `- ` bullets.
    /// Written after recording by Claude Code, Codex or Gemini CLI on this Mac, or by Oatmeal AI, or by an AI assistant over MCP.
    var notesMarkdown: String = ""
    /// The folder it's filed in (`MeetingFolder.id`), nil when unfiled.
    var folderID: UUID?
    var attendees: [String] = []

    init(title: String, startedAt: Date) {
        self.title = title
        self.startedAt = startedAt
    }
}

/// A folder for meetings ("Clients", "Acme", "1:1s"), Finder-style: folders can hold folders.
/// Meetings point at it by id, so deleting a folder hands its meetings to the folder above.
@Model
final class MeetingFolder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    /// The folder it sits in (`MeetingFolder.id`), nil at the top level.
    var parentID: UUID?

    init(name: String, parentID: UUID? = nil) {
        self.name = name
        self.parentID = parentID
    }
}

@Model
final class DictationEntry {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var destination: String = "app"
    var appName: String = ""
    var words: Int = 0
    var seconds: Double = 0

    init(text: String, destination: String, appName: String = "", seconds: Double = 0) {
        self.text = text
        self.destination = destination
        self.appName = appName
        self.words = text.split { $0.isWhitespace }.count
        self.seconds = seconds
    }

    /// Entries saved before word counts existed have 0; count them on the fly.
    var wordCount: Int { words > 0 ? words : text.split { $0.isWhitespace }.count }
}

extension Calendar {
    /// Gregorian, weeks starting Monday, in the user's time zone.
    static var oatmeal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = .current
        return c
    }
}

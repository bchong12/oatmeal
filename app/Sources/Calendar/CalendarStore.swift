import Foundation
import EventKit
import SwiftUI

/// A meeting from the user's calendars. Meetings show pale on Today and Week;
/// the user's own tasks stay solid.
struct CalEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    let colorHex: UInt32
    let source: String          // "Google", "iCloud", "Exchange", "Local"
    var attendees: [String] = []
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

/// Apple Calendar via EventKit. One permission brings in every account the Mac
/// already has (iCloud, Google, Exchange), with no sign-in and no review.
@MainActor
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()

    @Published private(set) var authorized = false
    @Published private(set) var calendars: [EKCalendar] = []
    @Published var hiddenCalendarIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenCalendars") ?? []) {
        didSet { UserDefaults.standard.set(Array(hiddenCalendarIDs), forKey: "hiddenCalendars"); changeToken += 1 }
    }
    @Published private(set) var changeToken = 0

    let store = EKEventStore()
    private var observer: NSObjectProtocol?

    private init() {
        refreshAuth()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }

    func refreshAuth() {
        authorized = status == .fullAccess
        if authorized { reload() }
    }

    func requestAccess() async {
        do {
            authorized = try await store.requestFullAccessToEvents()
        } catch {
            authorized = false
        }
        reload()
    }

    func reload() {
        guard authorized else { calendars = []; return }
        calendars = store.calendars(for: .event).sorted { $0.title < $1.title }
        changeToken += 1
    }

    /// Apple Calendar connected: it brings in every account on the Mac (iCloud, Google, Exchange).
    var anyConnected: Bool { authorized }

    func events(from start: Date, to end: Date) -> [CalEvent] { macEvents(from: start, to: end) }

    private func macEvents(from start: Date, to end: Date) -> [CalEvent] {
        guard authorized else { return [] }
        let visible = calendars.filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: visible)
        return store.events(matching: pred).map { e in
            CalEvent(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "Untitled", start: e.startDate, end: e.endDate,
                     isAllDay: e.isAllDay, calendarTitle: e.calendar.title, colorHex: Self.hex(e.calendar.cgColor),
                     source: Self.sourceName(e.calendar.source),
                     attendees: (e.attendees ?? []).compactMap { $0.name ?? $0.url.absoluteString.replacingOccurrences(of: "mailto:", with: "") })
        }.sorted { $0.start < $1.start }
    }

    func events(on day: Date) -> [CalEvent] {
        let s = Calendar.current.startOfDay(for: day)
        return events(from: s, to: s.addingTimeInterval(86_400))
    }

    /// The event happening right now (or starting within 2 minutes), for the pill's
    /// "meeting started" prompt.
    func currentEvent(now: Date = Date()) -> CalEvent? {
        events(from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(120))
            .first { !$0.isAllDay && $0.start <= now.addingTimeInterval(120) && $0.end > now }
    }

    // MARK: Helpers

    static func sourceName(_ s: EKSource?) -> String {
        guard let s else { return "Local" }
        let t = s.title.lowercased()
        if t.contains("gmail") || t.contains("google") || s.title.contains("@gmail") { return "Google" }
        switch s.sourceType {
        case .calDAV: return t.contains("icloud") ? "iCloud" : "Google"
        case .exchange: return "Exchange"
        case .local: return "Local"
        default: return s.title
        }
    }

    static func hex(_ c: CGColor?) -> UInt32 {
        guard let c, let comps = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return 0x7B66A8 }
        let r = UInt32(max(0, min(255, comps.redComponent * 255)))
        let g = UInt32(max(0, min(255, comps.greenComponent * 255)))
        let b = UInt32(max(0, min(255, comps.blueComponent * 255)))
        return (r << 16) | (g << 8) | b
    }
}

import Foundation
import UserNotifications
import EventKit

/// Granola-style: a notification as each calendar meeting starts, with a
/// "Take notes" button that starts recording straight away.
@MainActor
final class MeetingReminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MeetingReminders()
    private let center = UNUserNotificationCenter.current()
    private var timer: Timer?
    static let category = "DAYFORM_MEETING"
    static let takeNotes = "TAKE_NOTES"

    func start() {
        center.delegate = self
        let action = UNNotificationAction(identifier: Self.takeNotes, title: "Take notes", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [action], intentIdentifiers: [])])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        reschedule()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in MeetingReminders.shared.reschedule() }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
            Task { @MainActor in MeetingReminders.shared.reschedule() }
        }
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: "meetingReminders") as? Bool ?? true }

    /// Reminders for the next 24 hours of timed meetings, one minute before each starts.
    func reschedule() {
        center.removePendingNotificationRequests(withIdentifiers: scheduledIDs)
        scheduledIDs = []
        guard enabled else { return }
        let now = Date()
        let events = CalendarStore.shared.events(from: now, to: now.addingTimeInterval(86_400))
            .filter { !$0.isAllDay && $0.start > now.addingTimeInterval(30) }
            .prefix(20)
        for e in events {
            let content = UNMutableNotificationContent()
            content.title = e.title
            let who = e.attendees.prefix(3).joined(separator: ", ")
            content.body = "Starts \(e.start.formatted(date: .omitted, time: .shortened))" + (who.isEmpty ? "" : " · \(who)") + ". Take notes with Oatmeal?"
            content.categoryIdentifier = Self.category
            content.userInfo = ["title": e.title, "eventID": e.id]
            content.sound = .default
            let fire = max(e.start.addingTimeInterval(-60), now.addingTimeInterval(5))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSince(now), repeats: false)
            let id = "meeting-\(e.id)-\(Int(e.start.timeIntervalSince1970))"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            scheduledIDs.append(id)
        }
    }

    private var scheduledIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: "scheduledMeetingReminders") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "scheduledMeetingReminders") }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let title = response.notification.request.content.userInfo["title"] as? String ?? "Meeting"
        let tapped = response.actionIdentifier
        await MainActor.run {
            if tapped == MeetingReminders.takeNotes || tapped == UNNotificationDefaultActionIdentifier {
                Task { await PillController.shared.startMeeting(title: title) }
            }
        }
    }
}

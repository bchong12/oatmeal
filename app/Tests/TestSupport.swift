import Foundation
import SwiftData
@testable import Dayform

/// A local date built on Dayform's calendar (weeks start Monday).
func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    Calendar.dayform.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

/// A fresh in-memory store for one test.
@MainActor
func makeContext() throws -> (ModelContainer, ModelContext) {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Goal.self, DayTask.self, MeetingNote.self, MeetingFolder.self, DictationEntry.self,
                                       configurations: config)
    return (container, container.mainContext)
}

@MainActor
@discardableResult
func addDone(_ goal: Goal, at completed: Date, minutes: Int = 30, in context: ModelContext) -> DayTask {
    let t = DayTask(title: goal.name, day: completed, minutes: minutes, label: "Personal", goal: goal, source: "goal")
    context.insert(t)
    t.status = .done
    t.completedAt = completed
    return t
}

let plainCreature = Creature(shape: "arch", colour: "coral", prop: "")

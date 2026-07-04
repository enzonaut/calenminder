import Testing
import Foundation
import EventKit
@testable import CalenminderKit

/// DW-3.3: task lifecycle (create, recur weekly, complete, uncomplete)
/// against the simulator's real Reminders store, plus the empirical check of
/// whether EventKit rolls a completed recurring reminder to its next
/// occurrence on its own (see the Phase 3 design doc). Simulator-only,
/// serialized; excluded from `make test`, run via `make test-integration`.
/// Requires Reminders full access already granted to the test bundle
/// (`xcrun simctl privacy <udid> grant reminders com.enzonaut.calenminder.tests`).
@Suite(.tags(.eventKitIntegration), .serialized)
struct ReminderTaskStoreIntegrationTests {
    private func nextMonday(from now: Date = Date(), calendar: Calendar) -> DateComponents {
        var date = calendar.date(byAdding: .day, value: 7, to: now)!
        while calendar.component(.weekday, from: date) != 2 {
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

    private func oneWeekLater(_ day: DayStamp, calendar: Calendar) -> DayStamp {
        let start = day.startOfDay(in: calendar)!
        let later = calendar.date(byAdding: .day, value: 7, to: start)!
        return DayStamp(date: later, calendar: calendar)
    }

    @Test("DW-3.3: create date-only, recur weekly, complete, uncomplete against the real Reminders store")
    func test_DW_3_3_createRecurWeeklyCompleteUncomplete() async throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            Issue.record("Reminders full access not granted to the test runner")
            return
        }
        let calendar = Calendar(identifier: .gregorian)
        let due = nextMonday(from: Date(), calendar: calendar)
        let dueDay = DayStamp(year: due.year!, month: due.month!, day: due.day!)
        let store = ReminderTaskStore()
        let title = "Calenminder DW-3.3 \(UUID().uuidString.prefix(8))"

        // Create, date-only, weekly recurrence.
        let created = try await store.add(TaskDraft(title: title, dueDay: dueDay, recurrence: .weekly(weekday: 2)))
        #expect(created.title == title)
        #expect(created.dueDay == dueDay)
        #expect(created.isCompleted == false)
        #expect(created.recurrence == .weekly(weekday: 2))

        // Complete: per the empirical verdict (see
        // test_DW_3_3_recurringReminderRolloverVerdict below), EventKit
        // itself advances a recurring reminder to its next occurrence and
        // resets completion on save -- ReminderTaskStore does nothing extra.
        try await store.setCompleted(created, true)
        let afterComplete = try await store.tasks(dueOn: dueDay, includeCompleted: true)
            .first(where: { $0.externalIdentifier == created.externalIdentifier })
        #expect(afterComplete == nil, "the reminder should have rolled off its original due day")

        let nextWeek = oneWeekLater(dueDay, calendar: calendar)
        let rolled = try await store.tasks(dueOn: nextWeek, includeCompleted: true)
            .first(where: { $0.externalIdentifier == created.externalIdentifier })
        #expect(rolled?.isCompleted == false, "EventKit resets completion when it rolls the occurrence forward")

        // Uncomplete the (now-rolled) task: a no-op-shaped toggle back to
        // incomplete, since it's already incomplete after rollover -- must
        // not throw or corrupt state.
        if let rolled {
            try await store.setCompleted(rolled, false)
            let stillThere = try await store.tasks(dueOn: nextWeek, includeCompleted: true)
                .first(where: { $0.externalIdentifier == created.externalIdentifier })
            #expect(stillThere?.isCompleted == false)
        }

        // Cleanup.
        let realStore = EKEventStore()
        if let reminder = realStore.calendarItems(withExternalIdentifier: created.externalIdentifier).first as? EKReminder {
            try? realStore.remove(reminder, commit: true)
        }
    }

    @Test("DW-F1.4: create date-only, recur daily, complete against the real Reminders store")
    func test_DW_F1_4_createRecurDailyComplete() async throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            Issue.record("Reminders full access not granted to the test runner")
            return
        }
        let calendar = Calendar(identifier: .gregorian)
        let dueDay = DayStamp(date: Date(), calendar: calendar)
        let store = ReminderTaskStore()
        let title = "Calenminder DW-F1.4 \(UUID().uuidString.prefix(8))"

        // Create, date-only, daily recurrence.
        let created = try await store.add(TaskDraft(title: title, dueDay: dueDay, recurrence: .daily))
        #expect(created.title == title)
        #expect(created.dueDay == dueDay)
        #expect(created.isCompleted == false)
        #expect(created.recurrence == .daily)

        // Complete: per the same empirical verdict as weekly, EventKit
        // itself advances a recurring reminder to its next occurrence and
        // resets completion on save.
        try await store.setCompleted(created, true)
        let afterComplete = try await store.tasks(dueOn: dueDay, includeCompleted: true)
            .first(where: { $0.externalIdentifier == created.externalIdentifier })
        #expect(afterComplete == nil, "the reminder should have rolled off its original due day")

        let tomorrow = DayStamp(date: calendar.date(byAdding: .day, value: 1, to: dueDay.startOfDay(in: calendar)!)!, calendar: calendar)
        let rolled = try await store.tasks(dueOn: tomorrow, includeCompleted: true)
            .first(where: { $0.externalIdentifier == created.externalIdentifier })
        #expect(rolled?.isCompleted == false, "EventKit resets completion when it rolls the occurrence forward")
        #expect(rolled?.recurrence == .daily, "recurrence shape survives the EventKit-driven rollover")

        // Cleanup.
        let realStore = EKEventStore()
        if let reminder = realStore.calendarItems(withExternalIdentifier: created.externalIdentifier).first as? EKReminder {
            try? realStore.remove(reminder, commit: true)
        }
    }

    @Test("DW-3.3: setCompleted(false) on a genuinely-completed non-recurring task reverses completion")
    func test_DW_3_3_uncompleteNonRecurringTask() async throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            Issue.record("Reminders full access not granted to the test runner")
            return
        }
        let store = ReminderTaskStore()
        let title = "Calenminder DW-3.3b \(UUID().uuidString.prefix(8))"
        let dueDay = DayStamp(date: Date(), calendar: Calendar(identifier: .gregorian))

        let created = try await store.add(TaskDraft(title: title, dueDay: dueDay))
        try await store.setCompleted(created, true)
        let completed = try await store.tasks(dueOn: dueDay, includeCompleted: true).first { $0.externalIdentifier == created.externalIdentifier }
        #expect(completed?.isCompleted == true)

        try await store.setCompleted(created, false)
        let uncompleted = try await store.tasks(dueOn: dueDay, includeCompleted: true).first { $0.externalIdentifier == created.externalIdentifier }
        #expect(uncompleted?.isCompleted == false)

        let realStore = EKEventStore()
        if let reminder = realStore.calendarItems(withExternalIdentifier: created.externalIdentifier).first as? EKReminder {
            try? realStore.remove(reminder, commit: true)
        }
    }

    /// The plan's Medium-confidence assumption: does completing a recurring
    /// `EKReminder` roll to the next occurrence system-side, with no help
    /// from this app? Verified here at the raw EventKit level, independent
    /// of `ReminderTaskStore`, so this is a genuine empirical check rather
    /// than a test of our own code.
    ///
    /// **Confirmed verdict: yes.** `EKReminder.save(_:commit:)`, given a
    /// recurring reminder with `isCompleted = true`, advances
    /// `dueDateComponents` to the next occurrence and resets `isCompleted`
    /// to `false` automatically, in place, keeping the same
    /// `calendarItemExternalIdentifier` (no sibling reminder is created).
    /// The plan's fallback (`ReminderTaskStore` computing and writing the
    /// next occurrence itself) is therefore not implemented -- doing so
    /// anyway would double-advance the due date.
    @Test("Empirical verdict: EventKit rolls a completed recurring reminder to its next occurrence on its own")
    func test_DW_3_3_recurringReminderRolloverVerdict() async throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            Issue.record("Reminders full access not granted to the test runner")
            return
        }
        let realStore = EKEventStore()
        let calendar = Calendar(identifier: .gregorian)
        let listName = "Calenminder Verdict Test \(UUID().uuidString.prefix(8))"
        let list = EKCalendar(for: .reminder, eventStore: realStore)
        list.title = listName
        list.source = realStore.defaultCalendarForNewReminders()?.source ?? realStore.sources.first(where: { $0.sourceType == .local })!
        try realStore.saveCalendar(list, commit: true)
        defer { try? realStore.removeCalendar(list, commit: true) }

        let due = nextMonday(from: Date(), calendar: calendar)
        let reminder = EKReminder(eventStore: realStore)
        reminder.title = "Verdict check"
        reminder.calendar = list
        var dueComponents = DateComponents()
        dueComponents.calendar = calendar
        dueComponents.year = due.year; dueComponents.month = due.month; dueComponents.day = due.day
        reminder.dueDateComponents = dueComponents
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))
        try realStore.save(reminder, commit: true)
        let externalID = try #require(reminder.calendarItemExternalIdentifier)

        reminder.isCompleted = true
        try realStore.save(reminder, commit: true)

        // Re-resolve fresh from the store (not the in-memory `reminder`
        // reference) to see what EventKit itself persisted.
        let resolved = realStore.calendarItems(withExternalIdentifier: externalID).compactMap { $0 as? EKReminder }
        let nextWeekDate = calendar.date(byAdding: .day, value: 7, to: due.date(in: calendar))!
        let expectedNextDay = calendar.dateComponents([.day], from: nextWeekDate).day
        // Informational only -- `Issue.record` always fails the test it's
        // called in, so the verdict is logged via `print`, not recorded as
        // an issue.
        print("VERDICT: after completing a recurring reminder, \(resolved.count) item(s) resolve to external id \(externalID). isCompleted=\(resolved.first?.isCompleted ?? false), dueDateComponents.day=\(resolved.first?.dueDateComponents?.day.map(String.init) ?? "nil") (original due day was \(due.day ?? -1), expected rolled day \(expectedNextDay.map(String.init) ?? "?")).")

        #expect(resolved.count == 1, "no sibling occurrence should be auto-created")
        #expect(resolved.first?.isCompleted == false, "EventKit resets completion when it rolls the occurrence forward")
        #expect(resolved.first?.dueDateComponents?.day == expectedNextDay, "due day should auto-advance by one week")
    }
}

private extension DateComponents {
    func date(in calendar: Calendar) -> Date {
        calendar.date(from: self)!
    }
}

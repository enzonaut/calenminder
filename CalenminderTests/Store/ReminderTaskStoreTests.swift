import Testing
import Foundation
import EventKit
@testable import CalenminderKit

/// DW-3.1 (task half): day-scoped fetch and overdue lookback against
/// `FixtureCalendarProvider`. DW-3.4 (task half): typed permission errors.
/// Also covers the reminder-rollover fallback's *logic* (the empirical
/// question of whether it's needed at all is DW-3.3, integration-only) and
/// dirty cases beyond the DW floor.
struct ReminderTaskStoreTests {
    let cal = Calendar(identifier: .gregorian)

    func components(_ y: Int, _ m: Int, _ d: Int) -> DateComponents {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return c
    }

    // MARK: - DW-3.1: day-scoped fetch

    @Test("DW-3.1: tasks(dueOn:) returns only tasks due exactly that day")
    func test_DW_3_1_tasksDueOn_filtersToExactDay() async throws {
        let provider = FixtureCalendarProvider()
        let listID = try provider.taskListCalendar(named: ReminderTaskStore.listName)
        provider.reminders = [
            (RawReminderRecord(externalIdentifier: "today", title: "Today", dueDay: components(2026, 7, 3), isCompleted: false, recurrenceWeekday: nil), listID),
            (RawReminderRecord(externalIdentifier: "tomorrow", title: "Tomorrow", dueDay: components(2026, 7, 4), isCompleted: false, recurrenceWeekday: nil), listID),
        ]
        let store = ReminderTaskStore(provider: provider)

        let tasks = try await store.tasks(dueOn: DayStamp(year: 2026, month: 7, day: 3), includeCompleted: true)

        #expect(tasks.map(\.externalIdentifier) == ["today"])
    }

    @Test("DW-3.1: tasks(dueOn:includeCompleted: false) excludes completed tasks")
    func test_DW_3_1_tasksDueOn_excludesCompletedWhenNotIncluded() async throws {
        let provider = FixtureCalendarProvider()
        let listID = try provider.taskListCalendar(named: ReminderTaskStore.listName)
        provider.reminders = [
            (RawReminderRecord(externalIdentifier: "done", title: "Done", dueDay: components(2026, 7, 3), isCompleted: true, recurrenceWeekday: nil), listID),
            (RawReminderRecord(externalIdentifier: "open", title: "Open", dueDay: components(2026, 7, 3), isCompleted: false, recurrenceWeekday: nil), listID),
        ]
        let store = ReminderTaskStore(provider: provider)

        let tasks = try await store.tasks(dueOn: DayStamp(year: 2026, month: 7, day: 3), includeCompleted: false)

        #expect(tasks.map(\.externalIdentifier) == ["open"])
    }

    @Test("DW-3.1: incompleteTasks(overdueAsOf:) includes today and earlier incomplete tasks, not later or completed ones")
    func test_DW_3_1_incompleteTasksOverdueAsOf_includesPastAndTodayIncomplete() async throws {
        let provider = FixtureCalendarProvider()
        let listID = try provider.taskListCalendar(named: ReminderTaskStore.listName)
        provider.reminders = [
            (RawReminderRecord(externalIdentifier: "past", title: "Past", dueDay: components(2026, 7, 1), isCompleted: false, recurrenceWeekday: nil), listID),
            (RawReminderRecord(externalIdentifier: "today", title: "Today", dueDay: components(2026, 7, 3), isCompleted: false, recurrenceWeekday: nil), listID),
            (RawReminderRecord(externalIdentifier: "future", title: "Future", dueDay: components(2026, 7, 5), isCompleted: false, recurrenceWeekday: nil), listID),
            (RawReminderRecord(externalIdentifier: "pastDone", title: "Past done", dueDay: components(2026, 7, 1), isCompleted: true, recurrenceWeekday: nil), listID),
        ]
        let store = ReminderTaskStore(provider: provider)

        let overdue = try await store.incompleteTasks(overdueAsOf: DayStamp(year: 2026, month: 7, day: 3))

        #expect(Set(overdue.map(\.externalIdentifier)) == ["past", "today"])
    }

    // MARK: - DW-3.1: add / dedicated list

    @Test("DW-3.1: add(_:) creates the dedicated task list on first use")
    func test_DW_3_1_add_createsDedicatedListOnFirstUse() async throws {
        let provider = FixtureCalendarProvider()
        let store = ReminderTaskStore(provider: provider)

        let task = try await store.add(TaskDraft(title: "Water plants", dueDay: DayStamp(year: 2026, month: 7, day: 3)))

        #expect(provider.createdCalendars == [ReminderTaskStore.listName])
        #expect(task.title == "Water plants")
        #expect(task.isCompleted == false)
    }

    @Test("DW-3.1: add(_:) with a weekly recurrence round-trips through DayTask")
    func test_DW_3_1_add_weeklyRecurrenceRoundTrips() async throws {
        let provider = FixtureCalendarProvider()
        let store = ReminderTaskStore(provider: provider)

        let task = try await store.add(TaskDraft(title: "Recycling", dueDay: DayStamp(year: 2026, month: 7, day: 6), recurrence: .weekly(weekday: 2)))

        #expect(task.recurrence == .weekly(weekday: 2))
    }

    // MARK: - DW-3.4: typed permission errors

    @Test("DW-3.4: tasks(dueOn:) with denied access throws .accessDenied(.reminder)")
    func test_DW_3_4_tasksDueOn_deniedThrowsAccessDenied() async throws {
        let provider = FixtureCalendarProvider()
        provider.reminderAuthStatus = .denied
        let store = ReminderTaskStore(provider: provider)

        do {
            _ = try await store.tasks(dueOn: DayStamp(year: 2026, month: 7, day: 3), includeCompleted: true)
            Issue.record("expected accessDenied")
        } catch CalendarStoreError.accessDenied(let type) {
            #expect(type == .reminder)
        }
    }

    @Test("DW-3.4: notDetermined requests access and throws .accessDenied(.reminder) if the user declines")
    func test_DW_3_4_notDetermined_deniedRequestThrowsAccessDenied() async throws {
        let provider = FixtureCalendarProvider()
        provider.reminderAuthStatus = .notDetermined
        provider.requestAccessGranted = false
        let store = ReminderTaskStore(provider: provider)

        do {
            _ = try await store.tasks(dueOn: DayStamp(year: 2026, month: 7, day: 3), includeCompleted: true)
            Issue.record("expected accessDenied")
        } catch CalendarStoreError.accessDenied(let type) {
            #expect(type == .reminder)
        }
    }

    // MARK: - Dirty coverage beyond the DW floor

    @Test("setCompleted on a since-deleted task throws .itemDeletedUnderneath")
    func setCompletedOnDeletedTaskThrowsItemDeletedUnderneath() async throws {
        let provider = FixtureCalendarProvider()
        let store = ReminderTaskStore(provider: provider)
        let ghost = DayTask(externalIdentifier: "gone", title: "Gone", dueDay: DayStamp(year: 2026, month: 7, day: 3), isCompleted: false)

        do {
            try await store.setCompleted(ghost, true)
            Issue.record("expected itemDeletedUnderneath")
        } catch CalendarStoreError.itemDeletedUnderneath {
            // expected
        }
    }

    @Test("add(_:) wraps a provider save failure as .saveFailed")
    func addWrapsSaveFailureAsSaveFailed() async throws {
        let provider = FixtureCalendarProvider()
        provider.forcedSaveError = CocoaError(.fileWriteUnknown)
        let store = ReminderTaskStore(provider: provider)

        do {
            _ = try await store.add(TaskDraft(title: "T", dueDay: DayStamp(year: 2026, month: 7, day: 3)))
            Issue.record("expected saveFailed")
        } catch CalendarStoreError.saveFailed {
            // expected
        }
    }

    // MARK: - setCompleted is a plain pass-through, recurring or not (see
    // DW-3.3's empirical verdict: EventKit's own `save()` handles rollover
    // for a recurring reminder, so `ReminderTaskStore` does not -- and must
    // not, since doing so too would double-advance the due date).

    @Test("setCompleted(true) on a non-recurring task just marks it complete")
    func setCompletedTrue_nonRecurringTask_justCompletes() async throws {
        let provider = FixtureCalendarProvider()
        let listID = try provider.taskListCalendar(named: ReminderTaskStore.listName)
        provider.reminders = [(RawReminderRecord(externalIdentifier: "t1", title: "Once", dueDay: components(2026, 7, 3), isCompleted: false, recurrenceWeekday: nil), listID)]
        let store = ReminderTaskStore(provider: provider)
        let task = DayTask(externalIdentifier: "t1", title: "Once", dueDay: DayStamp(year: 2026, month: 7, day: 3), isCompleted: false)

        try await store.setCompleted(task, true)

        let record = provider.reminders.first(where: { $0.record.externalIdentifier == "t1" })!.record
        #expect(record.isCompleted == true)
        #expect(record.dueDay.day == 3)
    }

    @Test("setCompleted(true) on a recurring task marks it complete without this store touching the due day (that's EventKit's job, verified separately)")
    func setCompletedTrue_recurringTask_marksCompleteWithoutLocalReschedule() async throws {
        let provider = FixtureCalendarProvider()
        let listID = try provider.taskListCalendar(named: ReminderTaskStore.listName)
        // 2026-07-06 is a Monday (weekday 2).
        provider.reminders = [(RawReminderRecord(externalIdentifier: "t2", title: "Weekly", dueDay: components(2026, 7, 6), isCompleted: false, recurrenceWeekday: 2), listID)]
        let store = ReminderTaskStore(provider: provider)
        let task = DayTask(externalIdentifier: "t2", title: "Weekly", dueDay: DayStamp(year: 2026, month: 7, day: 6), isCompleted: false, recurrence: .weekly(weekday: 2))

        try await store.setCompleted(task, true)

        // The fixture (unlike the real system store) never advances dueDay
        // on its own, so if this assertion holds, `ReminderTaskStore` truly
        // isn't computing/writing a reschedule itself.
        let record = provider.reminders.first(where: { $0.record.externalIdentifier == "t2" })!.record
        #expect(record.isCompleted == true)
        #expect(record.dueDay.day == 6)
    }

    @Test("setCompleted(false) uncompletes the task as-is, with no reschedule")
    func setCompletedFalse_justUncompletes() async throws {
        let provider = FixtureCalendarProvider()
        let listID = try provider.taskListCalendar(named: ReminderTaskStore.listName)
        provider.reminders = [(RawReminderRecord(externalIdentifier: "t3", title: "Weekly", dueDay: components(2026, 7, 6), isCompleted: true, recurrenceWeekday: 2), listID)]
        let store = ReminderTaskStore(provider: provider)
        let task = DayTask(externalIdentifier: "t3", title: "Weekly", dueDay: DayStamp(year: 2026, month: 7, day: 6), isCompleted: true, recurrence: .weekly(weekday: 2))

        try await store.setCompleted(task, false)

        let record = provider.reminders.first(where: { $0.record.externalIdentifier == "t3" })!.record
        #expect(record.isCompleted == false)
        #expect(record.dueDay.day == 6)
    }
}

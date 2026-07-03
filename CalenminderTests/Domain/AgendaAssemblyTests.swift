import Testing
import Foundation
@testable import CalenminderKit

/// DW-2.2: agenda assembly - interleave order, declined excluded, completed-task
/// exclusion, overdue rollover. Plus dirty-input defense (T-2.3).
struct AgendaAssemblyTests {
    let cal = Fixture.calendar("America/New_York")

    /// The window for a single ordinary day, used by most cases.
    var window: DayWindow {
        DayWindow(day: DayStamp(year: 2026, month: 7, day: 3), calendar: cal)!
    }
    var today: DayStamp { DayStamp(year: 2026, month: 7, day: 3) }

    // MARK: interleave order

    @Test("DW-2.2: events are ordered all-day first, then chronologically by start")
    func test_DW_2_2_chronologicalInterleaveOrder() {
        let allDay = Fixture.event(
            id: "allday", title: "All day",
            start: Fixture.date(cal, 2026, 7, 3), end: Fixture.date(cal, 2026, 7, 4),
            allDay: true
        )
        let noon = Fixture.event(
            id: "noon", title: "Noon",
            start: Fixture.date(cal, 2026, 7, 3, 12), end: Fixture.date(cal, 2026, 7, 3, 13)
        )
        let nine = Fixture.event(
            id: "nine", title: "Nine",
            start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10)
        )
        // Deliberately unsorted input.
        let snapshot = assembleAgenda(
            events: [noon, allDay, nine],
            tasksDueToday: [], overdueTasks: [],
            window: window, filter: .agenda
        )
        #expect(snapshot.events.map(\.externalIdentifier) == ["allday", "nine", "noon"])
    }

    @Test("Simultaneous timed events tie-break deterministically by title")
    func simultaneousEventsTieBreakByTitle() {
        let start = Fixture.date(cal, 2026, 7, 3, 9)
        let end = Fixture.date(cal, 2026, 7, 3, 10)
        let bravo = Fixture.event(id: "b", title: "Bravo", start: start, end: end)
        let alpha = Fixture.event(id: "a", title: "Alpha", start: start, end: end)
        let snapshot = assembleAgenda(
            events: [bravo, alpha], tasksDueToday: [], overdueTasks: [],
            window: window, filter: .agenda
        )
        #expect(snapshot.events.map(\.title) == ["Alpha", "Bravo"])
    }

    // MARK: declined excluded

    @Test("DW-2.2: declined events are excluded from the agenda")
    func test_DW_2_2_declinedEventsExcluded() {
        let accepted = Fixture.event(
            id: "acc", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10),
            status: .accepted
        )
        let declined = Fixture.event(
            id: "dec", start: Fixture.date(cal, 2026, 7, 3, 11), end: Fixture.date(cal, 2026, 7, 3, 12),
            status: .declined
        )
        let snapshot = assembleAgenda(
            events: [accepted, declined], tasksDueToday: [], overdueTasks: [],
            window: window, filter: .agenda
        )
        #expect(snapshot.events.map(\.externalIdentifier) == ["acc"])
    }

    @Test("DW-2.2: needsAction (pending) invites are kept in the in-app agenda")
    func test_DW_2_2_needsActionKeptInAgenda() {
        let pending = Fixture.event(
            id: "pend", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10),
            status: .needsAction
        )
        let snapshot = assembleAgenda(
            events: [pending], tasksDueToday: [], overdueTasks: [],
            window: window, filter: .agenda
        )
        // Kept, and its pending marker is derivable from the participation value.
        #expect(snapshot.events.first?.participation == .needsAction)
    }

    // MARK: completed-task exclusion

    @Test("DW-2.2: completed tasks are excluded from the working set")
    func test_DW_2_2_completedTasksExcluded() {
        let done = Fixture.task(id: "done", due: today, completed: true)
        let open = Fixture.task(id: "open", due: today, completed: false)
        let snapshot = assembleAgenda(
            events: [], tasksDueToday: [done, open], overdueTasks: [],
            window: window, filter: .agenda
        )
        #expect(snapshot.tasks.map(\.externalIdentifier) == ["open"])
    }

    // MARK: overdue rollover

    @Test("DW-2.2: incomplete overdue tasks roll forward into today")
    func test_DW_2_2_overdueTasksRollOver() {
        let todayTask = Fixture.task(id: "today", title: "Today", due: today)
        let overdue = Fixture.task(
            id: "overdue", title: "Overdue",
            due: DayStamp(year: 2026, month: 7, day: 1)
        )
        let snapshot = assembleAgenda(
            events: [], tasksDueToday: [todayTask], overdueTasks: [overdue],
            window: window, filter: .agenda
        )
        // Both present; older overdue sorts first (by due day).
        #expect(snapshot.tasks.map(\.externalIdentifier) == ["overdue", "today"])
    }

    @Test("A task appearing in both today and overdue lists is deduplicated")
    func duplicateTaskDeduplicated() {
        let due = today
        let a = Fixture.task(id: "dup", due: due)
        let aAgain = Fixture.task(id: "dup", due: due)
        let snapshot = assembleAgenda(
            events: [], tasksDueToday: [a], overdueTasks: [aAgain],
            window: window, filter: .agenda
        )
        #expect(snapshot.tasks.count == 1)
    }

    // MARK: window membership applied during assembly

    @Test("Events outside the window are excluded by assembly")
    func eventsOutsideWindowExcluded() {
        let inside = Fixture.event(
            id: "in", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10)
        )
        let tomorrow = Fixture.event(
            id: "out", start: Fixture.date(cal, 2026, 7, 4, 9), end: Fixture.date(cal, 2026, 7, 4, 10)
        )
        let snapshot = assembleAgenda(
            events: [inside, tomorrow], tasksDueToday: [], overdueTasks: [],
            window: window, filter: .agenda
        )
        #expect(snapshot.events.map(\.externalIdentifier) == ["in"])
    }

    // MARK: widget filter

    @Test("Widget filter keeps only accepted/tentative/notInvited events")
    func widgetFilterExcludesDeclinedAndNeedsAction() {
        let base = Fixture.date(cal, 2026, 7, 3, 9)
        let events = [
            Fixture.event(id: "acc", start: base, end: base.addingTimeInterval(3600), status: .accepted),
            Fixture.event(id: "tent", start: base, end: base.addingTimeInterval(3600), status: .tentative),
            Fixture.event(id: "mine", start: base, end: base.addingTimeInterval(3600), status: .notInvited),
            Fixture.event(id: "dec", start: base, end: base.addingTimeInterval(3600), status: .declined),
            Fixture.event(id: "pend", start: base, end: base.addingTimeInterval(3600), status: .needsAction),
        ]
        let snapshot = assembleAgenda(
            events: events, tasksDueToday: [], overdueTasks: [],
            window: window, filter: .widget
        )
        #expect(Set(snapshot.events.map(\.externalIdentifier)) == ["acc", "tent", "mine"])
    }

    // MARK: dirty input (T-2.3)

    @Test("T-2.3: events with blank/garbled identifiers are excluded, no crash")
    func test_T_2_3_garbledIdentifierEventsExcluded() {
        let good = Fixture.event(
            id: "good", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10)
        )
        let blank = Fixture.event(
            id: "", start: Fixture.date(cal, 2026, 7, 3, 11), end: Fixture.date(cal, 2026, 7, 3, 12)
        )
        let whitespace = Fixture.event(
            id: "   ", start: Fixture.date(cal, 2026, 7, 3, 13), end: Fixture.date(cal, 2026, 7, 3, 14)
        )
        let snapshot = assembleAgenda(
            events: [good, blank, whitespace], tasksDueToday: [], overdueTasks: [],
            window: window, filter: .agenda
        )
        #expect(snapshot.events.map(\.externalIdentifier) == ["good"])
    }

    @Test("Tasks with blank identifiers are excluded, no crash")
    func garbledIdentifierTasksExcluded() {
        let good = Fixture.task(id: "good", due: today)
        let blank = Fixture.task(id: "  ", due: today)
        let snapshot = assembleAgenda(
            events: [], tasksDueToday: [good, blank], overdueTasks: [],
            window: window, filter: .agenda
        )
        #expect(snapshot.tasks.map(\.externalIdentifier) == ["good"])
    }

    @Test("Empty inputs assemble to an empty snapshot")
    func emptyInputsProduceEmptySnapshot() {
        let snapshot = assembleAgenda(
            events: [], tasksDueToday: [], overdueTasks: [],
            window: window, filter: .agenda
        )
        #expect(snapshot == AgendaSnapshot(events: [], tasks: []))
    }
}

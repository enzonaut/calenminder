import Testing
import Foundation
@testable import CalenminderKit

/// DW-5.3 (midnight-boundary entries) and DW-5.4 (overflow/empty states) -
/// all pure, no fakes needed beyond plain `Event`/`DayTask` fixtures.
struct WidgetTimelineAssemblyTests {
    let cal = Fixture.calendar("America/New_York")

    // MARK: - slate(from:budget:) (DW-5.4: overflow)

    @Test("DW-5.4: slate caps events and tasks to the budget and reports overflow counts")
    func test_DW_5_4_slateCapsRowsAndReportsOverflow() {
        let events = (1...4).map { Fixture.event(id: "e\($0)", start: Fixture.date(cal, 2026, 7, 3, $0), end: Fixture.date(cal, 2026, 7, 3, $0 + 1)) }
        let tasks = (1...4).map { Fixture.task(id: "t\($0)", due: DayStamp(year: 2026, month: 7, day: 3)) }
        let snapshot = AgendaSnapshot(events: events, tasks: tasks)

        let slate = WidgetTimelineAssembly.slate(from: snapshot, budget: .homeScreenSmall)

        #expect(slate.events.map(\.externalIdentifier) == ["e1", "e2"])
        #expect(slate.eventOverflowCount == 2)
        #expect(slate.tasks.map(\.externalIdentifier) == ["t1", "t2"])
        #expect(slate.taskOverflowCount == 2)
    }

    @Test("DW-5.4: slate on the Lock Screen budget caps to exactly one event and one task")
    func test_DW_5_4_lockScreenBudgetCapsToOneEach() {
        let events = [
            Fixture.event(id: "e1", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10)),
            Fixture.event(id: "e2", start: Fixture.date(cal, 2026, 7, 3, 11), end: Fixture.date(cal, 2026, 7, 3, 12)),
        ]
        let tasks = [Fixture.task(id: "t1", due: DayStamp(year: 2026, month: 7, day: 3)), Fixture.task(id: "t2", due: DayStamp(year: 2026, month: 7, day: 3))]
        let snapshot = AgendaSnapshot(events: events, tasks: tasks)

        let slate = WidgetTimelineAssembly.slate(from: snapshot, budget: .lockScreen)

        #expect(slate.events.map(\.externalIdentifier) == ["e1"])
        #expect(slate.eventOverflowCount == 1)
        #expect(slate.tasks.map(\.externalIdentifier) == ["t1"])
        #expect(slate.taskOverflowCount == 1)
    }

    @Test("DW-5.4: slate under budget has no overflow")
    func slateUnderBudgetHasNoOverflow() {
        let snapshot = AgendaSnapshot(
            events: [Fixture.event(id: "e1", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10))],
            tasks: []
        )
        let slate = WidgetTimelineAssembly.slate(from: snapshot, budget: .homeScreenMedium)
        #expect(slate.eventOverflowCount == 0)
        #expect(slate.taskOverflowCount == 0)
    }

    // MARK: - isEmpty (DW-5.4: empty state)

    @Test("DW-5.4: slate is empty only when there are no events, no tasks, and no overflow")
    func test_DW_5_4_slateIsEmptyOnlyWhenNothingToShow() {
        let emptySnapshot = AgendaSnapshot(events: [], tasks: [])
        #expect(WidgetTimelineAssembly.slate(from: emptySnapshot, budget: .homeScreenSmall).isEmpty)

        let withOneTask = AgendaSnapshot(events: [], tasks: [Fixture.task(id: "t1", due: DayStamp(year: 2026, month: 7, day: 3))])
        #expect(WidgetTimelineAssembly.slate(from: withOneTask, budget: .homeScreenSmall).isEmpty == false)

        // Everything overflows past a zero-row budget hypothetically covered
        // by lockScreen (1 max) with 2 tasks: not empty, since the overflow
        // count itself is content.
        let overflowOnly = AgendaSnapshot(events: [], tasks: [
            Fixture.task(id: "t1", due: DayStamp(year: 2026, month: 7, day: 3)),
            Fixture.task(id: "t2", due: DayStamp(year: 2026, month: 7, day: 3)),
        ])
        let slate = WidgetTimelineAssembly.slate(from: overflowOnly, budget: .lockScreen)
        #expect(slate.tasks.count == 1 && slate.taskOverflowCount == 1)
        #expect(slate.isEmpty == false)
    }

    // MARK: - content(from:budget:)

    @Test("content(from:) wraps a successful load as .available with the capped slate")
    func contentWrapsSuccessAsAvailable() {
        let snapshot = AgendaSnapshot(events: [], tasks: [Fixture.task(id: "t1", due: DayStamp(year: 2026, month: 7, day: 3))])
        let content = WidgetTimelineAssembly.content(from: .success(snapshot), budget: .homeScreenSmall)
        guard case .available(let slate) = content else {
            Issue.record("expected .available")
            return
        }
        #expect(slate.tasks.map(\.externalIdentifier) == ["t1"])
    }

    @Test("content(from:) passes a failed load through as .unavailable with the same reason")
    func contentPassesFailureThroughAsUnavailable() {
        let content = WidgetTimelineAssembly.content(from: .failure(.remindersAccessDenied), budget: .homeScreenSmall)
        #expect(content == .unavailable(.remindersAccessDenied))
    }

    // MARK: - entries(today:tomorrow:now:calendar:) (DW-5.3)

    @Test("DW-5.3: entries span the midnight boundary - today dated now, tomorrow dated at the next midnight")
    func test_DW_5_3_entriesSpanMidnightBoundary() {
        let now = Fixture.date(cal, 2026, 7, 3, 21, 30)
        let today = WidgetAgendaContent.available(WidgetAgendaSlate(events: [], eventOverflowCount: 0, tasks: [], taskOverflowCount: 0))
        let tomorrow = WidgetAgendaContent.unavailable(.loadFailed)

        let entries = WidgetTimelineAssembly.entries(today: today, tomorrow: tomorrow, now: now, calendar: cal)

        #expect(entries.count == 2)
        #expect(entries[0].date == now)
        #expect(entries[0].day == DayStamp(year: 2026, month: 7, day: 3))
        #expect(entries[0].content == today)

        let expectedMidnight = Fixture.date(cal, 2026, 7, 4, 0, 0)
        #expect(entries[1].date == expectedMidnight)
        #expect(entries[1].day == DayStamp(year: 2026, month: 7, day: 4))
        #expect(entries[1].content == tomorrow)
    }

    @Test("DW-5.3: entries are correctly ordered (today strictly before tomorrow's boundary)")
    func entriesAreChronologicallyOrdered() {
        let now = Fixture.date(cal, 2026, 7, 3, 8, 0)
        let content = WidgetAgendaContent.available(WidgetAgendaSlate(events: [], eventOverflowCount: 0, tasks: [], taskOverflowCount: 0))
        let entries = WidgetTimelineAssembly.entries(today: content, tomorrow: content, now: now, calendar: cal)
        #expect(entries[0].date < entries[1].date)
    }
}

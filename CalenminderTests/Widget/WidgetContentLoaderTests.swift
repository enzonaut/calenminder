import Testing
import Foundation
@testable import CalenminderKit

/// DW-5.1 (the widget's participation/completion filtering) and DW-5.4
/// (permission-missing state mapping).
struct WidgetContentLoaderTests {
    let cal = Fixture.calendar("America/New_York")
    var today: DayStamp { DayStamp(year: 2026, month: 7, day: 3) }

    // MARK: - DW-5.1: .widget filter wiring

    @Test("DW-5.1: loadSnapshot uses AgendaFilter.widget - declined and needsAction are absent, accepted/tentative/notInvited are present")
    func test_DW_5_1_loadSnapshotAppliesWidgetFilter() async {
        let events = FakeEventStore()
        events.events = [
            Fixture.event(id: "accepted", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10), status: .accepted),
            Fixture.event(id: "tentative", start: Fixture.date(cal, 2026, 7, 3, 11), end: Fixture.date(cal, 2026, 7, 3, 12), status: .tentative),
            Fixture.event(id: "notInvited", start: Fixture.date(cal, 2026, 7, 3, 13), end: Fixture.date(cal, 2026, 7, 3, 14), status: .notInvited),
            Fixture.event(id: "declined", start: Fixture.date(cal, 2026, 7, 3, 15), end: Fixture.date(cal, 2026, 7, 3, 16), status: .declined),
            Fixture.event(id: "needsAction", start: Fixture.date(cal, 2026, 7, 3, 17), end: Fixture.date(cal, 2026, 7, 3, 18), status: .needsAction),
        ]
        let tasks = FakeTaskStore()
        tasks.tasks = [
            Fixture.task(id: "incomplete", due: today),
            Fixture.task(id: "completed", due: today, completed: true),
        ]
        let service = AgendaService(eventStore: events, taskStore: tasks)

        let result = await WidgetContentLoader.loadSnapshot(day: today, calendar: cal, agendaService: service)

        guard case .success(let snapshot) = result else {
            Issue.record("expected .success")
            return
        }
        #expect(Set(snapshot.events.map(\.externalIdentifier)) == ["accepted", "tentative", "notInvited"])
        #expect(snapshot.tasks.map(\.externalIdentifier) == ["incomplete"], "completed items must be absent")
    }

    @Test("loadSnapshot returns an empty (not failed) snapshot when there is genuinely nothing due")
    func loadSnapshotReturnsEmptySnapshotWhenNothingDue() async {
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: FakeTaskStore())
        let result = await WidgetContentLoader.loadSnapshot(day: today, calendar: cal, agendaService: service)
        guard case .success(let snapshot) = result else {
            Issue.record("expected .success")
            return
        }
        #expect(snapshot.events.isEmpty)
        #expect(snapshot.tasks.isEmpty)
    }

    // MARK: - DW-5.4: permission-missing mapping

    @Test("DW-5.4: a Calendars access-denied failure maps to .calendarsAccessDenied")
    func test_DW_5_4_calendarsAccessDeniedMapsCorrectly() async {
        let events = FakeEventStore()
        events.fetchError = CalendarStoreError.accessDenied(.event)
        let service = AgendaService(eventStore: events, taskStore: FakeTaskStore())

        let result = await WidgetContentLoader.loadSnapshot(day: today, calendar: cal, agendaService: service)
        #expect(result == .failure(.calendarsAccessDenied))
    }

    @Test("DW-5.4: a Reminders access-denied failure maps to .remindersAccessDenied")
    func test_DW_5_4_remindersAccessDeniedMapsCorrectly() async {
        let tasks = FakeTaskStore()
        tasks.fetchError = CalendarStoreError.accessDenied(.reminder)
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: tasks)

        let result = await WidgetContentLoader.loadSnapshot(day: today, calendar: cal, agendaService: service)
        #expect(result == .failure(.remindersAccessDenied))
    }

    @Test("DW-5.4: reason(for:) maps every CalendarStoreError case, and anything else falls back to .loadFailed")
    func test_DW_5_4_reasonMapsEachAccessDeniedCase() {
        #expect(WidgetContentLoader.reason(for: CalendarStoreError.accessDenied(.event)) == .calendarsAccessDenied)
        #expect(WidgetContentLoader.reason(for: CalendarStoreError.accessDenied(.reminder)) == .remindersAccessDenied)
        #expect(WidgetContentLoader.reason(for: CalendarStoreError.writeOnlyAccess) == .calendarsAccessDenied)
        #expect(WidgetContentLoader.reason(for: CalendarStoreError.itemDeletedUnderneath) == .loadFailed)
        #expect(WidgetContentLoader.reason(for: CalendarStoreError.saveFailed(underlying: TestError.boom)) == .loadFailed)
        #expect(WidgetContentLoader.reason(for: TestError.boom) == .loadFailed, "a non-CalendarStoreError must degrade to the generic reason, never crash")
    }
}

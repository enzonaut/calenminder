import Testing
import Foundation
@testable import CalenminderKit

/// DW-4.1: AgendaService assembly/filter behavior against fake stores.
struct AgendaServiceTests {
    let cal = Fixture.calendar("America/New_York")
    var today: DayStamp { DayStamp(year: 2026, month: 7, day: 3) }
    var window: DayWindow { DayWindow(day: today, calendar: cal)! }

    private func makeService(
        events: FakeEventStore = FakeEventStore(),
        tasks: FakeTaskStore = FakeTaskStore(),
        directory: FakeCalendarDirectory = FakeCalendarDirectory(),
        visibility: FakeCalendarVisibilityStore = FakeCalendarVisibilityStore(),
        reloader: FakeWidgetReloader = FakeWidgetReloader()
    ) -> AgendaService {
        AgendaService(eventStore: events, taskStore: tasks, calendarDirectory: directory, calendarVisibility: visibility, widgetReloader: reloader)
    }

    @Test("DW-4.1: agenda(for:filter:) applies the participation filter via assembleAgenda")
    func test_DW_4_1_agendaAppliesParticipationFilter() async throws {
        let events = FakeEventStore()
        events.events = [
            Fixture.event(id: "acc", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10), status: .accepted),
            Fixture.event(id: "dec", start: Fixture.date(cal, 2026, 7, 3, 11), end: Fixture.date(cal, 2026, 7, 3, 12), status: .declined),
        ]
        let service = makeService(events: events)

        let snapshot = try await service.agenda(for: window, filter: .agenda)
        #expect(snapshot.events.map(\.externalIdentifier) == ["acc"])
    }

    @Test("DW-4.1: agenda(for:filter:) excludes events on calendars the user has hidden")
    func test_DW_4_1_agendaAppliesCalendarVisibilityFilter() async throws {
        let events = FakeEventStore()
        events.events = [
            Fixture.event(id: "visible", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10), calendar: "shown"),
            Fixture.event(id: "hidden", start: Fixture.date(cal, 2026, 7, 3, 11), end: Fixture.date(cal, 2026, 7, 3, 12), calendar: "hidden"),
        ]
        let visibility = FakeCalendarVisibilityStore()
        visibility.setVisible(false, calendarIdentifier: "hidden")
        let service = makeService(events: events, visibility: visibility)

        let snapshot = try await service.agenda(for: window, filter: .agenda)
        #expect(snapshot.events.map(\.externalIdentifier) == ["visible"])
    }

    @Test("DW-4.1: agenda(for:filter:) combines today's due tasks with the overdue lookback")
    func test_DW_4_1_agendaCombinesTodayAndOverdueTasks() async throws {
        let tasks = FakeTaskStore()
        tasks.tasks = [
            Fixture.task(id: "today", due: today),
            Fixture.task(id: "overdue", due: DayStamp(year: 2026, month: 7, day: 1)),
            Fixture.task(id: "done-today", due: today, completed: true),
        ]
        let service = makeService(tasks: tasks)

        let snapshot = try await service.agenda(for: window, filter: .agenda)
        #expect(Set(snapshot.tasks.map(\.externalIdentifier)) == ["today", "overdue"])
    }

    @Test("DW-4.1: agenda(for:filter:) derives the working day from window.start, not just window membership")
    func test_DW_4_1_agendaDerivesDayFromWindowStart() async throws {
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "t", due: today)]
        let service = makeService(tasks: tasks)

        let snapshot = try await service.agenda(for: window, filter: .agenda)
        #expect(snapshot.tasks.map(\.externalIdentifier) == ["t"])
    }

    @Test("DW-4.1: changes merges both stores' change streams into one")
    func test_DW_4_1_changesStreamMergesBothStores() async throws {
        let events = FakeEventStore()
        let tasks = FakeTaskStore()
        let service = makeService(events: events, tasks: tasks)

        var iterator = service.changes.makeAsyncIterator()

        events.fireChange()
        let first = await iterator.next()
        #expect(first != nil)

        tasks.fireChange()
        let second = await iterator.next()
        #expect(second != nil)
    }

    @Test("DW-4.1: a successful mutation triggers a widget reload")
    func test_DW_4_1_mutationsTriggerWidgetReload() async throws {
        let taskStore = FakeTaskStore()
        let reloader = FakeWidgetReloader()
        let service = makeService(tasks: taskStore, reloader: reloader)

        _ = try await service.addTask(TaskDraft(title: "New", dueDay: today))
        #expect(reloader.reloadCount == 1)
    }

    @Test("A failed mutation does not trigger a widget reload")
    func failedMutationDoesNotTriggerWidgetReload() async throws {
        let taskStore = FakeTaskStore()
        taskStore.addResult = .failure(TestError.boom)
        let reloader = FakeWidgetReloader()
        let service = makeService(tasks: taskStore, reloader: reloader)

        do {
            _ = try await service.addTask(TaskDraft(title: "New", dueDay: today))
            Issue.record("expected addTask to throw")
        } catch TestError.boom {
            // expected
        }
        #expect(reloader.reloadCount == 0)
    }

    @Test("resolveEvent finds an event by identity, ignoring participation status")
    func resolveEventIgnoresParticipationFilter() async throws {
        let events = FakeEventStore()
        let occurrence = Fixture.date(cal, 2026, 7, 3, 9)
        events.events = [Fixture.event(id: "dec", start: occurrence, end: occurrence.addingTimeInterval(3600), status: .declined, occurrence: occurrence)]
        let service = makeService(events: events)

        let found = try await service.resolveEvent(externalIdentifier: "dec", occurrenceDate: occurrence)
        #expect(found?.externalIdentifier == "dec")
    }

    @Test("resolveEvent returns nil, not an error, for an unknown identifier")
    func resolveEventReturnsNilForUnknownIdentifier() async throws {
        let service = makeService()
        let found = try await service.resolveEvent(externalIdentifier: "missing", occurrenceDate: Date())
        #expect(found == nil)
    }

    @Test("resolveTask finds a task due today, including completed ones")
    func resolveTaskFindsCompletedTaskDueToday() async throws {
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "done", due: today, completed: true)]
        let service = makeService(tasks: tasks)

        let found = try await service.resolveTask(externalIdentifier: "done", referenceDay: today)
        #expect(found?.externalIdentifier == "done")
    }

    @Test("resolveTask finds an overdue incomplete task")
    func resolveTaskFindsOverdueTask() async throws {
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "overdue", due: DayStamp(year: 2026, month: 7, day: 1))]
        let service = makeService(tasks: tasks)

        let found = try await service.resolveTask(externalIdentifier: "overdue", referenceDay: today)
        #expect(found?.externalIdentifier == "overdue")
    }

    @Test("resolveTask returns nil for a genuinely unknown identifier")
    func resolveTaskReturnsNilForUnknownIdentifier() async throws {
        let service = makeService()
        let found = try await service.resolveTask(externalIdentifier: "missing", referenceDay: today)
        #expect(found == nil)
    }

    @Test("completedTasks(dueOn:) returns only completed tasks for that day")
    func completedTasksReturnsOnlyCompleted() async throws {
        let tasks = FakeTaskStore()
        tasks.tasks = [
            Fixture.task(id: "done", due: today, completed: true),
            Fixture.task(id: "open", due: today, completed: false),
        ]
        let service = makeService(tasks: tasks)

        let completed = try await service.completedTasks(dueOn: today)
        #expect(completed.map(\.externalIdentifier) == ["done"])
    }

    @Test("calendars() overlays the visibility store's flag onto the directory's list")
    func calendarsOverlaysVisibility() async throws {
        let directory = FakeCalendarDirectory()
        directory.result = .success([
            EventCalendarInfo(identifier: "a", title: "A", colorRed: 1, colorGreen: 0, colorBlue: 0, isVisible: true),
            EventCalendarInfo(identifier: "b", title: "B", colorRed: 0, colorGreen: 1, colorBlue: 0, isVisible: true),
        ])
        let visibility = FakeCalendarVisibilityStore()
        visibility.setVisible(false, calendarIdentifier: "b")
        let service = makeService(directory: directory, visibility: visibility)

        let calendars = try await service.calendars()
        #expect(calendars.first(where: { $0.identifier == "a" })?.isVisible == true)
        #expect(calendars.first(where: { $0.identifier == "b" })?.isVisible == false)
    }

    @Test("setCalendarVisible persists through to the visibility store")
    func setCalendarVisiblePersists() {
        let visibility = FakeCalendarVisibilityStore()
        let service = makeService(visibility: visibility)

        service.setCalendarVisible(false, calendarIdentifier: "x")
        #expect(visibility.isVisible(calendarIdentifier: "x") == false)
    }

    // MARK: - Phase 5: completeTask(externalIdentifier:referenceDay:) (DW-5.2, DW-5.5)

    @Test("DW-5.2: completeTask marks a real task completed and reloads the widget")
    func test_DW_5_2_completeTaskMarksTaskCompletedAndReloads() async throws {
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "t1", due: today)]
        let reloader = FakeWidgetReloader()
        let service = makeService(tasks: tasks, reloader: reloader)

        let completed = await service.completeTask(externalIdentifier: "t1", referenceDay: today)

        #expect(completed == true)
        #expect(tasks.completionCalls.map(\.0.externalIdentifier) == ["t1"])
        #expect(tasks.completionCalls.map(\.1) == [true])
        #expect(reloader.reloadCount == 1)
    }

    @Test("DW-5.5: completeTask on an unknown task id is a graceful no-op that still reloads")
    func test_DW_5_5_completeTaskUnknownIdIsNoOpAndReloads() async throws {
        let tasks = FakeTaskStore()
        let reloader = FakeWidgetReloader()
        let service = makeService(tasks: tasks, reloader: reloader)

        let completed = await service.completeTask(externalIdentifier: "does-not-exist", referenceDay: today)

        #expect(completed == false)
        #expect(tasks.completionCalls.isEmpty)
        #expect(reloader.reloadCount == 1)
    }

    @Test("DW-5.5: completeTask on an already-completed task id is a graceful no-op that still reloads")
    func test_DW_5_5_completeTaskAlreadyCompletedIdIsNoOpAndReloads() async throws {
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "t1", due: today, completed: true)]
        let reloader = FakeWidgetReloader()
        let service = makeService(tasks: tasks, reloader: reloader)

        let completed = await service.completeTask(externalIdentifier: "t1", referenceDay: today)

        #expect(completed == false)
        #expect(tasks.completionCalls.isEmpty, "an already-completed task must not be re-saved")
        #expect(reloader.reloadCount == 1)
    }

    @Test("DW-5.5: completeTask swallows a store failure (e.g. deleted underneath) into a graceful no-op that still reloads")
    func test_DW_5_5_storeThrowDuringCompleteIsNoOpAndReloads() async throws {
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "t1", due: today)]
        tasks.setCompletedError = CalendarStoreError.itemDeletedUnderneath
        let reloader = FakeWidgetReloader()
        let service = makeService(tasks: tasks, reloader: reloader)

        let completed = await service.completeTask(externalIdentifier: "t1", referenceDay: today)

        #expect(completed == false)
        #expect(reloader.reloadCount == 1)
    }

    // MARK: - Feature 2: monthSummary(for:filter:) (DW-F2.1)

    private var monthWindow: DayWindow { DayWindow(month: MonthStamp(year: 2026, month: 7), calendar: cal)! }

    @Test("DW-F2.1: monthSummary marks hasEvents per agenda-filter participation semantics")
    func test_DW_F2_1_monthSummaryMarksHasEventsPerAgendaFilterSemantics() async throws {
        let events = FakeEventStore()
        events.events = [
            Fixture.event(id: "acc", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10), status: .accepted),
            Fixture.event(id: "dec", start: Fixture.date(cal, 2026, 7, 5, 9), end: Fixture.date(cal, 2026, 7, 5, 10), status: .declined),
        ]
        let service = makeService(events: events)

        let summary = try await service.monthSummary(for: monthWindow, filter: .agenda)

        #expect(summary[DayStamp(year: 2026, month: 7, day: 3)]?.hasEvents == true)
        // .agenda excludes declined invitations - no event dot for that day.
        #expect(summary[DayStamp(year: 2026, month: 7, day: 5)]?.hasEvents == false)
    }

    @Test("DW-F2.1: monthSummary excludes events on calendars the user has hidden")
    func test_DW_F2_1_monthSummaryExcludesHiddenCalendarEvents() async throws {
        let events = FakeEventStore()
        events.events = [
            Fixture.event(id: "hidden", start: Fixture.date(cal, 2026, 7, 10, 9), end: Fixture.date(cal, 2026, 7, 10, 10), calendar: "hidden"),
        ]
        let visibility = FakeCalendarVisibilityStore()
        visibility.setVisible(false, calendarIdentifier: "hidden")
        let service = makeService(events: events, visibility: visibility)

        let summary = try await service.monthSummary(for: monthWindow, filter: .agenda)

        #expect(summary[DayStamp(year: 2026, month: 7, day: 10)]?.hasEvents == false)
    }

    @Test("DW-F2.1: monthSummary counts incomplete tasks per day")
    func test_DW_F2_1_monthSummaryCountsIncompleteTasksPerDay() async throws {
        let tasks = FakeTaskStore()
        tasks.tasks = [
            Fixture.task(id: "t1", due: DayStamp(year: 2026, month: 7, day: 12)),
            Fixture.task(id: "t2", due: DayStamp(year: 2026, month: 7, day: 12)),
            Fixture.task(id: "t3", due: DayStamp(year: 2026, month: 7, day: 13)),
        ]
        let service = makeService(tasks: tasks)

        let summary = try await service.monthSummary(for: monthWindow, filter: .agenda)

        #expect(summary[DayStamp(year: 2026, month: 7, day: 12)]?.incompleteTaskCount == 2)
        #expect(summary[DayStamp(year: 2026, month: 7, day: 13)]?.incompleteTaskCount == 1)
    }

    @Test("DW-F2.1: monthSummary does not count completed tasks")
    func test_DW_F2_1_monthSummaryExcludesCompletedTasks() async throws {
        let tasks = FakeTaskStore()
        tasks.tasks = [
            Fixture.task(id: "done", due: DayStamp(year: 2026, month: 7, day: 14), completed: true),
            Fixture.task(id: "open", due: DayStamp(year: 2026, month: 7, day: 14), completed: false),
        ]
        let service = makeService(tasks: tasks)

        let summary = try await service.monthSummary(for: monthWindow, filter: .agenda)

        #expect(summary[DayStamp(year: 2026, month: 7, day: 14)]?.incompleteTaskCount == 1)
    }

    @Test("DW-F2.1: monthSummary marks every day a multi-day all-day event spans")
    func test_DW_F2_1_monthSummaryHandlesMultiDayAllDayEvent() async throws {
        let events = FakeEventStore()
        events.events = [
            Fixture.event(
                id: "trip",
                start: Fixture.date(cal, 2026, 7, 20, 0),
                end: Fixture.date(cal, 2026, 7, 23, 0),
                allDay: true
            ),
        ]
        let service = makeService(events: events)

        let summary = try await service.monthSummary(for: monthWindow, filter: .agenda)

        #expect(summary[DayStamp(year: 2026, month: 7, day: 20)]?.hasEvents == true)
        #expect(summary[DayStamp(year: 2026, month: 7, day: 21)]?.hasEvents == true)
        #expect(summary[DayStamp(year: 2026, month: 7, day: 22)]?.hasEvents == true)
        #expect(summary[DayStamp(year: 2026, month: 7, day: 23)]?.hasEvents == false)
    }

    @Test("DW-F2.1: an empty month has no indicators on any day")
    func test_DW_F2_1_monthSummaryEmptyMonthHasNoIndicators() async throws {
        let service = makeService()

        let summary = try await service.monthSummary(for: monthWindow, filter: .agenda)

        #expect(summary.count == 31)
        #expect(summary.values.allSatisfy { $0.hasEvents == false && $0.incompleteTaskCount == 0 })
    }

    @Test("DW-F2.1: monthSummary fetches tasks with exactly one bounded range call, never per-day")
    func test_DW_F2_1_monthSummaryFetchesTasksOnce() async throws {
        let tasks = FakeTaskStore()
        let service = makeService(tasks: tasks)

        _ = try await service.monthSummary(for: monthWindow, filter: .agenda)

        #expect(tasks.incompleteTasksDueBetweenCallCount == 1)
    }

    @Test("Phase 5: reloadWidgets() triggers a widget reload with no store call")
    func test_reloadWidgetsTriggersReload() async throws {
        let reloader = FakeWidgetReloader()
        let service = makeService(reloader: reloader)

        service.reloadWidgets()

        #expect(reloader.reloadCount == 1)
    }
}

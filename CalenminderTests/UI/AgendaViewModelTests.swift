import Testing
import Foundation
@testable import Calenminder
@testable import CalenminderKit

@MainActor
struct AgendaViewModelTests {
    let cal = Fixture.calendar("America/New_York")
    var today: DayStamp { DayStamp(date: Date(), calendar: Calendar.current) }

    private func makeViewModel(
        events: FakeEventStore = FakeEventStore(),
        tasks: FakeTaskStore = FakeTaskStore(),
        day: DayStamp? = nil
    ) -> (AgendaViewModel, FakeEventStore, FakeTaskStore) {
        let service = AgendaService(eventStore: events, taskStore: tasks)
        let viewModel = AgendaViewModel(agendaService: service, day: day, calendar: .current)
        return (viewModel, events, tasks)
    }

    @Test("DW-4.3: load() populates snapshot from the agenda service")
    func loadPopulatesSnapshot() async {
        let events = FakeEventStore()
        let day = today
        let window = DayWindow(day: day, calendar: .current)!
        events.events = [Fixture.event(id: "e1", start: window.start.addingTimeInterval(3600), end: window.start.addingTimeInterval(7200))]
        let (viewModel, _, _) = makeViewModel(events: events, day: day)

        await viewModel.load()

        #expect(viewModel.snapshot.events.map(\.externalIdentifier) == ["e1"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test("DW-4.3: load() surfaces a store error rather than leaving a stale silent snapshot")
    func loadSurfacesError() async {
        let events = FakeEventStore()
        events.fetchError = TestError.boom
        let (viewModel, _, _) = makeViewModel(events: events)

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
    }

    @Test("goToNextDay/goToPreviousDay/goToToday change the viewed day and reload")
    func dayNavigationReloads() async {
        let day = today
        let (viewModel, _, _) = makeViewModel(day: day)
        await viewModel.load()

        viewModel.goToNextDay()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(viewModel.day != day)

        viewModel.goToToday()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(viewModel.day == day)
    }

    @Test("DW-4.3: completing a task optimistically removes it from the working set")
    func completingTaskOptimisticallyRemovesFromSnapshot() async {
        let day = today
        let tasks = FakeTaskStore()
        let task = Fixture.task(id: "t1", due: day)
        tasks.tasks = [task]
        let (viewModel, _, _) = makeViewModel(tasks: tasks, day: day)
        await viewModel.load()
        #expect(viewModel.snapshot.tasks.map(\.externalIdentifier) == ["t1"])

        await viewModel.toggleTaskCompletion(task)

        #expect(viewModel.snapshot.tasks.isEmpty)
        #expect(viewModel.completedToday.map(\.externalIdentifier) == ["t1"])
    }

    @Test("DW-4.3: a failed task completion rolls back the optimistic snapshot and surfaces an error")
    func failedTaskCompletionRollsBack() async {
        let day = today
        let tasks = FakeTaskStore()
        let task = Fixture.task(id: "t1", due: day)
        tasks.tasks = [task]
        let (viewModel, _, _) = makeViewModel(tasks: tasks, day: day)
        await viewModel.load()

        tasks.setCompletedError = TestError.boom

        await viewModel.toggleTaskCompletion(task)

        #expect(viewModel.snapshot.tasks.map(\.externalIdentifier) == ["t1"])
        #expect(viewModel.completedToday.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("DW-4.3: a failed event delete rolls back the optimistic snapshot and surfaces an error")
    func failedDeleteRollsBack() async {
        let day = today
        let events = FakeEventStore()
        let window = DayWindow(day: day, calendar: .current)!
        let event = Fixture.event(id: "e1", start: window.start.addingTimeInterval(3600), end: window.start.addingTimeInterval(7200))
        events.events = [event]
        events.deleteError = TestError.boom
        let (viewModel, _, _) = makeViewModel(events: events, day: day)
        await viewModel.load()

        let succeeded = await viewModel.deleteEvent(event, span: .thisEvent)

        #expect(succeeded == false)
        #expect(viewModel.snapshot.events.map(\.externalIdentifier) == ["e1"])
        #expect(viewModel.errorMessage != nil)
    }

    @Test("A successful event delete removes it and does not restore it on reload")
    func successfulDeleteRemainsRemoved() async {
        let day = today
        let events = FakeEventStore()
        let window = DayWindow(day: day, calendar: .current)!
        let event = Fixture.event(id: "e1", start: window.start.addingTimeInterval(3600), end: window.start.addingTimeInterval(7200))
        events.events = [event]
        let (viewModel, _, _) = makeViewModel(events: events, day: day)
        await viewModel.load()

        let succeeded = await viewModel.deleteEvent(event, span: .thisEvent)

        #expect(succeeded == true)
        #expect(viewModel.snapshot.events.isEmpty)
    }

    @Test("DW-4.3: a failed event update rolls back the optimistic snapshot")
    func failedUpdateRollsBack() async {
        let day = today
        let events = FakeEventStore()
        let window = DayWindow(day: day, calendar: .current)!
        let event = Fixture.event(id: "e1", title: "Original", start: window.start.addingTimeInterval(3600), end: window.start.addingTimeInterval(7200))
        events.events = [event]
        events.updateError = TestError.boom
        let (viewModel, _, _) = makeViewModel(events: events, day: day)
        await viewModel.load()

        let updated = Fixture.event(id: "e1", title: "Changed", start: event.start, end: event.end)
        let succeeded = await viewModel.updateEvent(event, applying: updated, span: .thisEvent)

        #expect(succeeded == false)
        #expect(viewModel.snapshot.events.first?.title == "Original")
        #expect(viewModel.errorMessage != nil)
    }

    // MARK: - Midnight rollover (plan edge case: "midnight rollover while app foregrounded")

    /// Mutable clock for driving the view model's injected `now()` across a
    /// simulated midnight.
    private final class MutableClock {
        var current: Date
        init(_ current: Date) { self.current = current }
    }

    @Test("Edge: foregrounding after midnight resets a today-following view to the new today")
    func foregroundAfterMidnightResetsToNewToday() async {
        let cal = Fixture.calendar("America/New_York")
        let clock = MutableClock(Fixture.date(cal, 2026, 7, 3, 12))
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: FakeTaskStore())
        let viewModel = AgendaViewModel(
            agendaService: service, calendar: cal,
            now: { clock.current }, notificationCenter: NotificationCenter()
        )
        await viewModel.load()
        #expect(viewModel.day == DayStamp(year: 2026, month: 7, day: 3))

        // Midnight passes while backgrounded; the app then foregrounds.
        clock.current = Fixture.date(cal, 2026, 7, 4, 0, 5)
        await viewModel.handleForeground()

        #expect(viewModel.day == DayStamp(year: 2026, month: 7, day: 4))
    }

    @Test("Edge: foregrounding after midnight does NOT reset a manually chosen day")
    func foregroundAfterMidnightKeepsManuallyChosenDay() async {
        let cal = Fixture.calendar("America/New_York")
        let clock = MutableClock(Fixture.date(cal, 2026, 7, 3, 12))
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: FakeTaskStore())
        let viewModel = AgendaViewModel(
            agendaService: service, calendar: cal,
            now: { clock.current }, notificationCenter: NotificationCenter()
        )
        await viewModel.load()

        // User deliberately navigates back one day.
        viewModel.goToPreviousDay()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(viewModel.day == DayStamp(year: 2026, month: 7, day: 2))

        // Midnight passes while backgrounded; the app then foregrounds.
        clock.current = Fixture.date(cal, 2026, 7, 4, 0, 5)
        await viewModel.handleForeground()

        #expect(viewModel.day == DayStamp(year: 2026, month: 7, day: 2), "a deliberately chosen day must not be yanked to the new today")
    }

    @Test("Edge: .NSCalendarDayChanged while foregrounded updates a today-following view")
    func dayChangedNotificationUpdatesTodayFollowingView() async {
        let cal = Fixture.calendar("America/New_York")
        let clock = MutableClock(Fixture.date(cal, 2026, 7, 3, 23, 59))
        let center = NotificationCenter()
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: FakeTaskStore())
        let viewModel = AgendaViewModel(
            agendaService: service, calendar: cal,
            now: { clock.current }, notificationCenter: center
        )
        await viewModel.load()
        #expect(viewModel.day == DayStamp(year: 2026, month: 7, day: 3))

        // The civil day rolls over while the app stays foregrounded.
        clock.current = Fixture.date(cal, 2026, 7, 4, 0, 0)
        center.post(name: .NSCalendarDayChanged, object: nil)

        // The observer hops to the main actor asynchronously; poll briefly.
        let newToday = DayStamp(year: 2026, month: 7, day: 4)
        for _ in 0..<50 where viewModel.day != newToday {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(viewModel.day == newToday)
    }

    @Test("Edge: .NSCalendarDayChanged does NOT move a manually chosen day")
    func dayChangedNotificationKeepsManuallyChosenDay() async {
        let cal = Fixture.calendar("America/New_York")
        let clock = MutableClock(Fixture.date(cal, 2026, 7, 3, 23, 59))
        let center = NotificationCenter()
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: FakeTaskStore())
        let viewModel = AgendaViewModel(
            agendaService: service, calendar: cal,
            now: { clock.current }, notificationCenter: center
        )
        await viewModel.load()

        viewModel.goToPreviousDay()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(viewModel.day == DayStamp(year: 2026, month: 7, day: 2))

        clock.current = Fixture.date(cal, 2026, 7, 4, 0, 0)
        center.post(name: .NSCalendarDayChanged, object: nil)
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(viewModel.day == DayStamp(year: 2026, month: 7, day: 2), "a manually chosen day must survive the day-changed notification")
    }

    @Test("Tapping Today after manual navigation resumes following today across midnight")
    func goToTodayResumesFollowingToday() async {
        let cal = Fixture.calendar("America/New_York")
        let clock = MutableClock(Fixture.date(cal, 2026, 7, 3, 12))
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: FakeTaskStore())
        let viewModel = AgendaViewModel(
            agendaService: service, calendar: cal,
            now: { clock.current }, notificationCenter: NotificationCenter()
        )
        await viewModel.load()

        // Manual navigation away stops following; Today resumes it.
        viewModel.goToPreviousDay()
        try? await Task.sleep(nanoseconds: 50_000_000)
        viewModel.goToToday()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(viewModel.day == DayStamp(year: 2026, month: 7, day: 3))

        clock.current = Fixture.date(cal, 2026, 7, 4, 9, 0)
        await viewModel.handleForeground()

        #expect(viewModel.day == DayStamp(year: 2026, month: 7, day: 4))
    }

    @Test("resolveEvent/resolveTask delegate through to the agenda service")
    func resolveDelegatesToService() async throws {
        let day = today
        let events = FakeEventStore()
        let occurrence = Date()
        events.events = [Fixture.event(id: "e1", start: occurrence, end: occurrence.addingTimeInterval(3600), occurrence: occurrence)]
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "t1", due: day)]
        let (viewModel, _, _) = makeViewModel(events: events, tasks: tasks, day: day)

        let foundEvent = try await viewModel.resolveEvent(externalIdentifier: "e1", occurrenceDate: occurrence)
        #expect(foundEvent?.externalIdentifier == "e1")

        let foundTask = try await viewModel.resolveTask(externalIdentifier: "t1")
        #expect(foundTask?.externalIdentifier == "t1")
    }
}

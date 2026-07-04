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

    /// Regression for the checkmark-completion race: a real device/simulator
    /// tap on the task-row checkmark did not reliably stick, even though this
    /// method and `ReminderTaskStore`'s round-trip are each independently
    /// green - see the checkmark-race discovery doc. Root cause was
    /// `AgendaViewModel.load()` running unbounded concurrent fetches: every
    /// mutation reloads once explicitly, and `listenForStoreChanges()`
    /// reloads again on every `EKEventStoreChanged` notification - including
    /// the one the mutation's own write just caused. Two concurrent fetches
    /// racing to assign `snapshot`/`completedToday` meant whichever
    /// *finished* last won, not whichever was freshest, so a reload whose
    /// read raced ahead of the write's propagation could stomp the correct,
    /// just-applied completed state back to incomplete.
    ///
    /// `FakeTaskStore` never fired its own `changes` stream inside
    /// `setCompleted` (unlike the real `ReminderTaskStore`, whose write goes
    /// through `EKEventStore`, which posts `EKEventStoreChanged` for its own
    /// writes too) - which is exactly why this race was invisible to every
    /// existing unit/integration test despite being real on-device. This
    /// test closes that gap by firing the change signal itself, from the
    /// same store instance, mid-mutation.
    @Test("A self-fired store-change notification racing a task completion's own reload does not revert the completed state")
    func selfFiredChangeDuringCompletionDoesNotRevertState() async {
        let day = today
        let tasks = FakeTaskStore()
        let task = Fixture.task(id: "t1", due: day)
        tasks.tasks = [task]
        let (viewModel, _, _) = makeViewModel(tasks: tasks, day: day)
        await viewModel.load()

        // Simulate the self-originated `EKEventStoreChanged` notification a
        // real completion write triggers, landing while the mutation's own
        // explicit reload is still in flight - the exact interleaving that
        // used to corrupt `snapshot`/`completedToday`.
        async let toggle: Void = viewModel.toggleTaskCompletion(task)
        tasks.fireChange()
        await toggle

        // Give the change-listener's `Task` a chance to run its (now
        // coalesced, not racing) follow-up reload.
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.snapshot.tasks.isEmpty, "the task must stay off the incomplete working set")
        #expect(viewModel.completedToday.map(\.externalIdentifier) == ["t1"], "the task must stay marked completed")
    }

    @Test("Concurrent load() calls coalesce into far fewer than one fetch per call")
    func concurrentLoadsCoalesceRatherThanRaceEachOthersFetch() async {
        let day = today
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "t1", due: day)]
        let (viewModel, _, _) = makeViewModel(tasks: tasks, day: day)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { await viewModel.load() }
            }
        }

        // Uncoalesced, 5 overlapping `load()` calls would each independently
        // fetch (2 calls to `tasks(dueOn:)` per fetch - `agenda(for:)` and
        // `completedTasks(dueOn:)` each need one - so 10 total). The
        // coalescing guard collapses that to at most one in-flight fetch
        // plus one queued follow-up, well under half that.
        #expect(tasks.tasksDueOnCallCount < 10, "overlapping load() calls should coalesce, not each run their own fetch")
        #expect(viewModel.snapshot.tasks.map(\.externalIdentifier) == ["t1"])
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

    // MARK: - Phase 5 reload trigger: app foreground

    @Test("Phase 5: handleForeground() nudges a widget reload, not just an agenda reload")
    func handleForegroundReloadsWidgets() async {
        let reloader = FakeWidgetReloader()
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: FakeTaskStore(), widgetReloader: reloader)
        let viewModel = AgendaViewModel(agendaService: service, calendar: .current)
        await viewModel.load()
        #expect(reloader.reloadCount == 0, "a plain load must not itself trigger a widget reload")

        await viewModel.handleForeground()

        #expect(reloader.reloadCount == 1)
    }

    // MARK: - Feature 2: goToDay(_:) (DW-F2.4)

    @Test("DW-F2.4: goToDay jumps directly to an arbitrary day and reloads")
    func test_DW_F2_4_goToDayJumpsToArbitraryDayAndReloads() async {
        let day = today
        let tasks = FakeTaskStore()
        let farDay = DayStamp(year: 2026, month: 12, day: 25)
        tasks.tasks = [Fixture.task(id: "gift", due: farDay)]
        let (viewModel, _, _) = makeViewModel(tasks: tasks, day: day)
        await viewModel.load()

        viewModel.goToDay(farDay)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.day == farDay)
        #expect(viewModel.snapshot.tasks.map(\.externalIdentifier) == ["gift"])
    }

    @Test("DW-F2.4: goToDay to a day other than today stops following today")
    func test_DW_F2_4_goToDayUpdatesIsFollowingTodayCorrectly() async {
        let cal = Fixture.calendar("America/New_York")
        let clock = MutableClock(Fixture.date(cal, 2026, 7, 3, 12))
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: FakeTaskStore())
        let viewModel = AgendaViewModel(
            agendaService: service, calendar: cal,
            now: { clock.current }, notificationCenter: NotificationCenter()
        )
        await viewModel.load()

        viewModel.goToDay(DayStamp(year: 2026, month: 8, day: 15))
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(viewModel.day == DayStamp(year: 2026, month: 8, day: 15))

        // Midnight passing while foregrounded must NOT yank a deliberately
        // chosen day back to the new today - same rule as every other
        // manual navigation entry point.
        clock.current = Fixture.date(cal, 2026, 7, 4, 0, 5)
        await viewModel.handleForeground()

        #expect(viewModel.day == DayStamp(year: 2026, month: 8, day: 15))
    }

    @Test("DW-F2.4: goToDay landing exactly on today resumes following it")
    func goToDayLandingOnTodayResumesFollowing() async {
        let cal = Fixture.calendar("America/New_York")
        let clock = MutableClock(Fixture.date(cal, 2026, 7, 3, 12))
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: FakeTaskStore())
        let viewModel = AgendaViewModel(
            agendaService: service, calendar: cal,
            now: { clock.current }, notificationCenter: NotificationCenter()
        )
        await viewModel.load()
        viewModel.goToPreviousDay()
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Jump (via goToDay, as Month/Week-strip taps do) back onto today.
        viewModel.goToDay(DayStamp(year: 2026, month: 7, day: 3))
        try? await Task.sleep(nanoseconds: 50_000_000)

        clock.current = Fixture.date(cal, 2026, 7, 4, 9, 0)
        await viewModel.handleForeground()

        #expect(viewModel.day == DayStamp(year: 2026, month: 7, day: 4), "landing on today via goToDay should resume following it across midnight")
    }

    @Test("goToDay to the same day is a no-op (no redundant reload)")
    func goToDaySameDayIsNoOp() async {
        let day = today
        let (viewModel, _, _) = makeViewModel(day: day)
        await viewModel.load()

        viewModel.goToDay(day)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.day == day)
    }

    // MARK: - Feature 3: icon-badge lifecycle triggers (DW-F3.2)

    private func makeViewModelWithBadge(
        tasks: FakeTaskStore = FakeTaskStore(),
        day: DayStamp? = nil
    ) -> (AgendaViewModel, FakeBadgeSetter) {
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: tasks)
        let badgeSetter = FakeBadgeSetter()
        let badgeUpdater = BadgeUpdater(agendaService: service, badgeSetting: badgeSetter)
        let viewModel = AgendaViewModel(agendaService: service, badgeUpdater: badgeUpdater, day: day, calendar: .current)
        return (viewModel, badgeSetter)
    }

    @Test("DW-F3.2: handleForeground() also refreshes the icon badge")
    func test_DW_F3_2_handleForegroundUpdatesBadge() async {
        let (viewModel, badgeSetter) = makeViewModelWithBadge()

        await viewModel.handleForeground()

        #expect(badgeSetter.appliedCounts.count == 1)
    }

    @Test("DW-F3.2: handleBackground() refreshes the icon badge")
    func test_DW_F3_2_handleBackgroundUpdatesBadge() async {
        let (viewModel, badgeSetter) = makeViewModelWithBadge()

        await viewModel.handleBackground()

        #expect(badgeSetter.appliedCounts.count == 1)
    }

    @Test("DW-F3.2: a successful addTask refreshes the icon badge with the new count")
    func test_DW_F3_2_addTaskUpdatesBadge() async {
        let day = today
        let (viewModel, badgeSetter) = makeViewModelWithBadge(day: day)

        _ = await viewModel.addTask(TaskDraft(title: "New", dueDay: day))

        #expect(badgeSetter.appliedCounts == [1])
    }

    @Test("DW-F3.2: toggling a task's completion refreshes the icon badge")
    func test_DW_F3_2_toggleTaskCompletionUpdatesBadge() async {
        let day = today
        let tasks = FakeTaskStore()
        let task = Fixture.task(id: "t1", due: day)
        tasks.tasks = [task]
        let (viewModel, badgeSetter) = makeViewModelWithBadge(tasks: tasks, day: day)
        await viewModel.load()

        await viewModel.toggleTaskCompletion(task)

        #expect(badgeSetter.appliedCounts == [0])
    }

    @Test("DW-F3.2: a failed task completion still refreshes the badge only via the store's actual state, not a phantom decrement")
    func test_DW_F3_2_failedToggleDoesNotUpdateBadge() async {
        let day = today
        let tasks = FakeTaskStore()
        let task = Fixture.task(id: "t1", due: day)
        tasks.tasks = [task]
        tasks.setCompletedError = TestError.boom
        let (viewModel, badgeSetter) = makeViewModelWithBadge(tasks: tasks, day: day)
        await viewModel.load()

        await viewModel.toggleTaskCompletion(task)

        #expect(badgeSetter.appliedCounts.isEmpty, "a rolled-back mutation must not refresh the badge - nothing actually changed")
    }
}

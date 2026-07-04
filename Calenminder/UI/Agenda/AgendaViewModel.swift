import Foundation
import CalenminderKit

/// The agenda screen's single source of truth, and the one place mutations
/// are applied optimistically and rolled back on failure (see the Phase 4
/// design doc's "Design: UI mutation ownership"). Every other feature view
/// model (`EventEditViewModel`, `TaskComposerViewModel`) reports its result
/// back here rather than talking to `AgendaService` directly, so there is
/// exactly one place that can get optimistic rollback wrong.
@MainActor
final class AgendaViewModel: ObservableObject {
    @Published private(set) var day: DayStamp
    @Published private(set) var snapshot: AgendaSnapshot = AgendaSnapshot(events: [], tasks: [])
    @Published private(set) var completedToday: [DayTask] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let agendaService: AgendaService
    /// Feature 3: shared badge orchestrator. Defaults to a fresh
    /// `BadgeUpdater` built over `agendaService` when the caller does not
    /// supply one - keeps every existing production and test call site of
    /// this initializer compiling unchanged; tests that care about badge
    /// behavior inject one built over a fake `BadgeSetting`.
    private let badgeUpdater: BadgeUpdater
    private let calendar: Calendar
    /// Injectable clock so midnight-rollover behavior is unit-testable; the
    /// production default is the real clock.
    private let now: () -> Date
    private let notificationCenter: NotificationCenter
    private var changeListenerTask: Task<Void, Never>?
    private var dayChangeObserver: NSObjectProtocol?

    /// Whether the view is auto-following "today" (the launch default and
    /// the state after tapping Today), as opposed to a day the user
    /// deliberately navigated to. Only a today-following view snaps to the
    /// new today when the civil day rolls over - a user who paged to next
    /// Tuesday must never be yanked back by midnight or a foreground.
    private var isFollowingToday: Bool

    init(
        agendaService: AgendaService,
        badgeUpdater: BadgeUpdater? = nil,
        day: DayStamp? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = .default
    ) {
        self.agendaService = agendaService
        self.badgeUpdater = badgeUpdater ?? BadgeUpdater(agendaService: agendaService)
        self.calendar = calendar
        self.now = now
        self.notificationCenter = notificationCenter
        let today = DayStamp(date: now(), calendar: calendar)
        let resolvedDay = day ?? today
        self.day = resolvedDay
        self.isFollowingToday = resolvedDay == today
        listenForStoreChanges()
        observeCalendarDayChange()
    }

    deinit {
        changeListenerTask?.cancel()
        if let dayChangeObserver {
            notificationCenter.removeObserver(dayChangeObserver)
        }
    }

    // MARK: - Loading

    /// Whether a `fetchAndApply()` is currently in flight.
    private var isReloadInFlight = false
    /// Whether another `load()` was requested while one was already in
    /// flight - honored as exactly one more `fetchAndApply()` once the
    /// in-flight one finishes, never a growing backlog.
    private var isReloadPending = false

    /// Coalescing gate in front of the real fetch (`fetchAndApply()`).
    ///
    /// `load()` has more callers than just the initial `.task` view
    /// modifier: every mutation (`toggleTaskCompletion`, `addTask`, ...)
    /// re-fetches right after its own write succeeds, *and*
    /// `listenForStoreChanges()` independently re-fetches on every
    /// `EKEventStoreChanged` notification - including the one that write
    /// itself just caused (EventKit does not distinguish "my own write" from
    /// "someone else changed it"). Those two triggers land within
    /// milliseconds of each other. Previously each ran its own concurrent
    /// `fetchAndApply()` and whichever happened to *finish* last (not
    /// whichever was fresher) won, unconditionally overwriting `snapshot`/
    /// `completedToday` - so a reload whose read raced ahead of the write's
    /// full propagation through EventKit's reminder store could stomp the
    /// correct, just-applied completed state back to incomplete. That is the
    /// checkmark-tap flake: the write always succeeded (`ReminderTaskStore`
    /// round-trips are independently verified), only the *display* of it
    /// could lose the race.
    ///
    /// Fix: never run two `fetchAndApply()`s concurrently. If one is already
    /// in flight, don't start a second one racing it - remember one more
    /// reload is owed, and run exactly one right after the current one
    /// finishes. That later reload reads `day` fresh at the moment it runs
    /// (never a stale captured value), so it is never incorrect to run - it
    /// naturally lands after the original write has had more time to
    /// propagate, without ever guessing at or hard-coding a delay.
    func load() async {
        guard !isReloadInFlight else {
            isReloadPending = true
            return
        }
        isReloadInFlight = true
        await fetchAndApply()
        isReloadInFlight = false
        if isReloadPending {
            isReloadPending = false
            await load()
        }
    }

    /// The actual fetch-and-assign; only ever run one at a time - see
    /// `load()`'s coalescing gate above.
    private func fetchAndApply() async {
        guard let window = DayWindow(day: day, calendar: calendar) else {
            errorMessage = "Something went wrong determining that day's date."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            async let snapshotResult = agendaService.agenda(for: window, filter: .agenda)
            async let completedResult = agendaService.completedTasks(dueOn: day)
            snapshot = try await snapshotResult
            completedToday = try await completedResult
            errorMessage = nil
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    func refresh() async {
        await load()
    }

    func goToToday() {
        day = DayStamp(date: now(), calendar: calendar)
        isFollowingToday = true
        Task { await load() }
    }

    /// Feature 2: jump directly to an arbitrary day (a Month-view day tap, or
    /// a Week-strip tap) - unlike `shiftDay`, the target is not relative to
    /// the current day. Same "is this still following today" bookkeeping as
    /// every other day-changing entry point: landing exactly on today counts
    /// as following it again, landing anywhere else is a deliberate choice.
    func goToDay(_ newDay: DayStamp) {
        guard newDay != day else { return }
        day = newDay
        isFollowingToday = day == DayStamp(date: now(), calendar: calendar)
        Task { await load() }
    }

    func goToPreviousDay() {
        shiftDay(by: -1)
    }

    func goToNextDay() {
        shiftDay(by: 1)
    }

    private func shiftDay(by value: Int) {
        guard
            let start = day.startOfDay(in: calendar),
            let shifted = calendar.date(byAdding: .day, value: value, to: start)
        else { return }
        day = DayStamp(date: shifted, calendar: calendar)
        // Paging back onto the current today counts as following it again;
        // landing anywhere else is a deliberate manual choice.
        isFollowingToday = day == DayStamp(date: now(), calendar: calendar)
        Task { await load() }
    }

    // MARK: - Task mutations (optimistic)

    func addTask(_ draft: TaskDraft) async -> DayTask? {
        do {
            let created = try await agendaService.addTask(draft)
            await load()
            // Feature 3: a new incomplete task can push today's count up.
            await badgeUpdater.updateBadge()
            return created
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
            return nil
        }
    }

    /// Toggling completion removes/re-adds the task from the visible
    /// incomplete working set immediately; on failure the previous snapshot
    /// (and completed-today list) is restored and the error surfaced.
    func toggleTaskCompletion(_ task: DayTask) async {
        let previousSnapshot = snapshot
        let previousCompleted = completedToday
        let completing = !task.isCompleted

        if completing {
            snapshot = AgendaSnapshot(events: snapshot.events, tasks: snapshot.tasks.filter { $0.id != task.id })
            completedToday = previousCompleted + [DayTask(
                externalIdentifier: task.externalIdentifier, title: task.title,
                dueDay: task.dueDay, isCompleted: true, recurrence: task.recurrence
            )]
        } else {
            completedToday = previousCompleted.filter { $0.id != task.id }
        }

        do {
            try await agendaService.setTaskCompleted(task, completing)
            // Refetch for authoritative state - a completed recurring task
            // rolls to its next occurrence system-side (Phase 3 finding),
            // which the optimistic patch above cannot know how to represent.
            await load()
            // Feature 3: completing/uncompleting a task changes today's count.
            await badgeUpdater.updateBadge()
        } catch {
            snapshot = previousSnapshot
            completedToday = previousCompleted
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    // MARK: - Event mutations (optimistic)

    func createEvent(_ draft: EventDraft) async -> Event? {
        do {
            let created = try await agendaService.createEvent(draft)
            await load()
            return created
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
            return nil
        }
    }

    func updateEvent(_ original: Event, applying updated: Event, span: EditSpan) async -> Bool {
        let previous = snapshot
        snapshot = AgendaSnapshot(
            events: snapshot.events.map { $0.id == original.id ? updated : $0 },
            tasks: snapshot.tasks
        )
        do {
            try await agendaService.updateEvent(updated, span: span)
            await load()
            return true
        } catch {
            snapshot = previous
            errorMessage = ErrorPresentation.message(for: error)
            return false
        }
    }

    func deleteEvent(_ event: Event, span: EditSpan) async -> Bool {
        let previous = snapshot
        snapshot = AgendaSnapshot(events: snapshot.events.filter { $0.id != event.id }, tasks: snapshot.tasks)
        do {
            try await agendaService.deleteEvent(event, span: span)
            return true
        } catch {
            snapshot = previous
            errorMessage = ErrorPresentation.message(for: error)
            return false
        }
    }

    // MARK: - Identity resolution (delegated, for detail/deep-link screens)

    func resolveEvent(externalIdentifier: String, occurrenceDate: Date) async throws -> Event? {
        try await agendaService.resolveEvent(externalIdentifier: externalIdentifier, occurrenceDate: occurrenceDate)
    }

    func resolveTask(externalIdentifier: String) async throws -> DayTask? {
        try await agendaService.resolveTask(externalIdentifier: externalIdentifier, referenceDay: day)
    }

    func calendars() async throws -> [EventCalendarInfo] {
        try await agendaService.calendars()
    }

    func setCalendarVisible(_ visible: Bool, calendarIdentifier: String) async {
        agendaService.setCalendarVisible(visible, calendarIdentifier: calendarIdentifier)
        await load()
    }

    // MARK: - Change-driven / foreground refresh

    private func listenForStoreChanges() {
        changeListenerTask = Task { [weak self] in
            guard let self else { return }
            for await _ in agendaService.changes {
                await self.load()
            }
        }
    }

    /// Called by the root view on `scenePhase` transitioning to `.active`.
    /// Owning this trigger here (not inside `AgendaService`) keeps
    /// app-lifecycle awareness out of the shared framework - see the Phase 4
    /// design doc. If midnight passed while the app was backgrounded and the
    /// view was following today, snap to the new today before reloading so
    /// the user never wakes up to yesterday's agenda.
    func handleForeground() async {
        resetToTodayIfFollowing()
        await load()
        // Phase 5 reload trigger: "app foreground" - see
        // `AgendaService.reloadWidgets()`'s doc comment for why this is
        // nudged explicitly rather than left to WidgetKit's own budget.
        agendaService.reloadWidgets()
        // Feature 3 reload trigger: "app foreground" - also the lazy,
        // once-per-session-effectively point where badge authorization is
        // first requested (see `BadgeSetting`'s doc comment).
        await badgeUpdater.updateBadge()
    }

    /// Called by the root view on `scenePhase` transitioning to
    /// `.background` (Feature 3's "app background/resign-active" trigger).
    /// Recomputing here - not just on foreground - means the icon badge
    /// reflects the state the user is leaving behind (e.g. they just
    /// completed the last task and are switching apps) rather than staying
    /// stale until they happen to come back.
    func handleBackground() async {
        await badgeUpdater.updateBadge()
    }

    /// Midnight rollover while the app stays foregrounded: the system posts
    /// `.NSCalendarDayChanged` when the civil day changes (including timezone
    /// and DST-driven changes), which covers the case `scenePhase` never
    /// fires for. Same only-if-following-today rule as `handleForeground()`.
    private func observeCalendarDayChange() {
        dayChangeObserver = notificationCenter.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.resetToTodayIfFollowing()
                await self.load()
            }
        }
    }

    /// If (and only if) the view is auto-following today, move `day` to the
    /// current today. A manually chosen day is left exactly where it is.
    private func resetToTodayIfFollowing() {
        guard isFollowingToday else { return }
        let today = DayStamp(date: now(), calendar: calendar)
        if day != today {
            day = today
        }
    }
}

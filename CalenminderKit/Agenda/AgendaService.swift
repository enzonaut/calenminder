import Foundation
import WidgetKit

/// Triggers a widget-timeline reload after a mutation. Abstracted so tests
/// never touch the real `WidgetCenter` (which has no meaningful behavior to
/// assert on in a unit-test host with no installed widget).
public protocol WidgetReloading: AnyObject {
    func reloadAllTimelines()
}

/// Production `WidgetReloading`, backed by `WidgetCenter`. A widget *kind* is
/// deliberately not targeted here: Phase 5 has not named its widget kinds
/// yet, and reloading all timelines is cheap and always correct, just
/// possibly slightly wasteful if the device has other widgets from this app
/// that do not need it - there are none until Phase 5 ships the first one.
public final class SystemWidgetReloader: WidgetReloading {
    public init() {}

    public func reloadAllTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// The agenda coordinator over both `EventStoring` and `TaskStoring`: the one
/// seam the app and (from Phase 5) the widget both call for everything
/// agenda-shaped. Stateless by design (see the Phase 4 design doc's
/// "Design: AgendaService" comparison) - every call fetches fresh from the
/// underlying stores, which is what makes it equally correct for a
/// long-lived app process and a widget process that runs once per timeline
/// entry. Change-driven refresh and foreground refresh are both *triggered*
/// by callers (via `changes` and, in the app, `scenePhase`); this type only
/// provides the mechanism, never reaches into app lifecycle itself.
public final class AgendaService {
    private let eventStore: EventStoring
    private let taskStore: TaskStoring
    private let calendarDirectory: EventCalendarDirectory
    private let calendarVisibility: CalendarVisibilityStoring
    private let widgetReloader: WidgetReloading

    /// Merged, coarse change signal from both stores. One shared stream per
    /// `AgendaService` instance (not per-caller) - multiple listeners each
    /// get their own iteration since `AsyncStream` supports only one
    /// consumer, so this is built once at init and callers should keep a
    /// single long-lived subscriber (the app's `AgendaViewModel` does).
    public let changes: AsyncStream<Void>
    private let changesContinuation: AsyncStream<Void>.Continuation
    private let relayTasks: [Task<Void, Never>]

    public init(
        eventStore: EventStoring,
        taskStore: TaskStoring,
        calendarDirectory: EventCalendarDirectory = SystemEventCalendarDirectory(),
        calendarVisibility: CalendarVisibilityStoring = CalendarVisibilityStore(),
        widgetReloader: WidgetReloading = SystemWidgetReloader()
    ) {
        self.eventStore = eventStore
        self.taskStore = taskStore
        self.calendarDirectory = calendarDirectory
        self.calendarVisibility = calendarVisibility
        self.widgetReloader = widgetReloader

        var continuation: AsyncStream<Void>.Continuation!
        self.changes = AsyncStream { continuation = $0 }
        self.changesContinuation = continuation

        let eventChanges = eventStore.changes
        let taskChanges = taskStore.changes
        let eventRelay = Task { for await _ in eventChanges { continuation.yield(()) } }
        let taskRelay = Task { for await _ in taskChanges { continuation.yield(()) } }
        self.relayTasks = [eventRelay, taskRelay]
        continuation.onTermination = { _ in
            eventRelay.cancel()
            taskRelay.cancel()
        }
    }

    deinit {
        changesContinuation.finish()
        for task in relayTasks { task.cancel() }
    }

    // MARK: - Pinned seam

    /// Events + the incomplete task working set for the civil day
    /// `window.start` falls on (per `window.calendar`), filtered by
    /// participation (`filter`) and by which calendars the user has hidden.
    /// A `window` spanning more than one day still resolves tasks to that
    /// single day - the agenda UI only ever views one day at a time.
    public func agenda(for window: DayWindow, filter: AgendaFilter) async throws -> AgendaSnapshot {
        let day = DayStamp(date: window.start, calendar: window.calendar)

        async let eventsResult = eventStore.events(in: window)
        async let tasksDueTodayResult = taskStore.tasks(dueOn: day, includeCompleted: false)
        async let overdueTasksResult = taskStore.incompleteTasks(overdueAsOf: day)

        let events = try await eventsResult
        let tasksDueToday = try await tasksDueTodayResult
        let overdueTasks = try await overdueTasksResult

        let visibleEvents = filterByCalendarVisibility(events)

        return assembleAgenda(
            events: visibleEvents,
            tasksDueToday: tasksDueToday,
            overdueTasks: overdueTasks,
            window: window,
            filter: filter
        )
    }

    /// Feature 2: per-day event/incomplete-task indicators for Month view,
    /// covering every civil day `window` spans. Exactly two fetches
    /// regardless of the window's length (one events window-fetch, one
    /// bounded incomplete-tasks range-fetch) - never a per-day fetch loop.
    /// `window` is typically a whole month (`DayWindow(month:calendar:)`),
    /// but this works for any window; `AgendaService` never needs to know
    /// "month" is a domain concept - that stays a UI/Month-view detail.
    public func monthSummary(for window: DayWindow, filter: AgendaFilter) async throws -> [DayStamp: DaySummary] {
        let firstDay = DayStamp(date: window.start, calendar: window.calendar)
        let lastDay = DayStamp(date: window.end.addingTimeInterval(-1), calendar: window.calendar)

        async let eventsResult = eventStore.events(in: window)
        async let tasksResult = taskStore.incompleteTasks(dueBetween: firstDay, and: lastDay)

        let visibleEvents = filterByCalendarVisibility(try await eventsResult)
        let incompleteTasks = try await tasksResult

        return assembleMonthSummary(events: visibleEvents, incompleteTasks: incompleteTasks, window: window, filter: filter)
    }

    /// Feature 3: the icon-badge count for `day` - today's incomplete tasks
    /// plus the overdue-incomplete lookback, deduped exactly like
    /// `agenda(for:filter:)`'s own task list (`incompleteTaskCount` shares
    /// its merge rule with `assembleAgenda` so the two can never disagree),
    /// computed from two `TaskStoring` fetches only - no events fetch, since
    /// the badge never needs one. Additive: does not change
    /// `agenda(for:filter:)`'s contract or behavior. Throws on a genuine
    /// store failure (e.g. Reminders access denied) exactly like every
    /// other read path here - callers that want "denial is silently 0"
    /// (Feature 3's `BadgeUpdater`) make that choice themselves, one layer
    /// up, the same way `completeTask` already swallows its own failures
    /// rather than this type doing it silently.
    public func badgeCount(asOf day: DayStamp) async throws -> Int {
        async let tasksDueTodayResult = taskStore.tasks(dueOn: day, includeCompleted: false)
        async let overdueTasksResult = taskStore.incompleteTasks(overdueAsOf: day)
        return incompleteTaskCount(tasksDueToday: try await tasksDueTodayResult, overdueTasks: try await overdueTasksResult)
    }

    /// Today's completed tasks - deliberately outside `AgendaSnapshot`
    /// (whose `tasks` is documented as the incomplete working set only), for
    /// the agenda UI's collapsible "Completed" section, which is how a task
    /// can be found again to uncomplete it.
    public func completedTasks(dueOn day: DayStamp) async throws -> [DayTask] {
        try await taskStore.tasks(dueOn: day, includeCompleted: true).filter(\.isCompleted)
    }

    // MARK: - Identity resolution (detail view, deep links)

    /// Resolves one event occurrence by its durable identity, ignoring
    /// participation/visibility filters (a detail screen must be able to
    /// show a declined or hidden-calendar event the user navigated to
    /// directly). `nil` means "not found" (unknown or deleted identifier) -
    /// this never throws for a plain miss, only for access/store failures,
    /// so callers can render a not-found state without a `do/catch`.
    public func resolveEvent(externalIdentifier: String, occurrenceDate: Date) async throws -> Event? {
        let calendar = Calendar.current
        let searchStart = calendar.date(byAdding: .day, value: -1, to: occurrenceDate) ?? occurrenceDate
        let searchEnd = calendar.date(byAdding: .day, value: 1, to: occurrenceDate) ?? occurrenceDate
        let window = DayWindow(start: searchStart, end: searchEnd, calendar: calendar)
        let events = try await eventStore.events(in: window)
        return events.first {
            $0.externalIdentifier == externalIdentifier
                && abs($0.occurrenceDate.timeIntervalSince(occurrenceDate)) < 1
        }
    }

    /// Best-effort resolution of a task by identifier alone (`TaskStoring`
    /// has no by-id lookup): searches `referenceDay`'s due list (including
    /// completed) plus the unbounded overdue-incomplete lookback. A task
    /// completed on some other day and not due `referenceDay` will not
    /// resolve here - it correctly returns `nil` (not-found), never throws
    /// or crashes for that case.
    public func resolveTask(externalIdentifier: String, referenceDay: DayStamp) async throws -> DayTask? {
        async let dueTodayResult = taskStore.tasks(dueOn: referenceDay, includeCompleted: true)
        async let overdueResult = taskStore.incompleteTasks(overdueAsOf: referenceDay)
        let candidates = try await dueTodayResult + (try await overdueResult)
        return candidates.first { $0.externalIdentifier == externalIdentifier }
    }

    // MARK: - Mutations

    /// Every mutation below reloads widget timelines only *after* the store
    /// call succeeds - a failed mutation changed nothing, so nothing needs
    /// re-rendering (and a `defer` here would fire on the throw path too,
    /// which is why this is explicit rather than `defer`).

    public func createEvent(_ draft: EventDraft) async throws -> Event {
        let created = try await eventStore.create(draft)
        widgetReloader.reloadAllTimelines()
        return created
    }

    public func updateEvent(_ event: Event, span: EditSpan) async throws {
        try await eventStore.update(event, span: span)
        widgetReloader.reloadAllTimelines()
    }

    public func deleteEvent(_ event: Event, span: EditSpan) async throws {
        try await eventStore.delete(event, span: span)
        widgetReloader.reloadAllTimelines()
    }

    public func addTask(_ draft: TaskDraft) async throws -> DayTask {
        let created = try await taskStore.add(draft)
        widgetReloader.reloadAllTimelines()
        return created
    }

    public func setTaskCompleted(_ task: DayTask, _ completed: Bool) async throws {
        try await taskStore.setCompleted(task, completed)
        widgetReloader.reloadAllTimelines()
    }

    // PSEUDOCODE: completeTask(externalIdentifier:referenceDay:)
    //   However this returns, reload widget timelines afterward (unlike the
    //   mutations above, this must happen even on the no-op path - that
    //   reload is what corrects a stale cached row, DW-5.5).
    //   Try to resolve a DayTask for externalIdentifier anchored at
    //   referenceDay; if resolution fails or finds nothing, or the task is
    //   already completed -> no-op, return false.
    //   Otherwise try to mark it completed; on success return true, on any
    //   thrown error (e.g. deleted underneath) -> no-op, return false.

    /// Completes a task by durable identifier alone, for the widget's
    /// button-driven `CompleteTaskIntent` (Phase 5), which only ever has a
    /// task ID - not a full `DayTask` snapshot - to act on.
    ///
    /// Graceful by design (DW-5.5): a stale cached timeline row can point at
    /// a task that was deleted or already completed by another client (the
    /// app, the Reminders app, another device) since the timeline entry was
    /// generated. Neither case is an error the widget process has anywhere
    /// to show - both become a silent no-op. Unlike every other mutation
    /// above (which only reloads *after* a successful store call, since a
    /// failed mutation changed nothing worth re-rendering), this always
    /// reloads: the entire point of reloading here is to correct the stale
    /// cache the no-op itself revealed. An unexpected store failure (e.g.
    /// `itemDeletedUnderneath`) is swallowed into the same no-op rather than
    /// propagated, for the same reason an App Intent's `perform()` throwing
    /// produces a system error alert - worse than doing nothing and letting
    /// the reload show reality.
    ///
    /// Returns whether a real completion happened, for tests; the intent
    /// itself discards this (it must never surface success/failure as a
    /// dialog either way).
    @discardableResult
    public func completeTask(externalIdentifier: String, referenceDay: DayStamp) async -> Bool {
        defer { widgetReloader.reloadAllTimelines() }
        guard
            let task = try? await resolveTask(externalIdentifier: externalIdentifier, referenceDay: referenceDay),
            !task.isCompleted
        else { return false }
        do {
            try await taskStore.setCompleted(task, true)
            return true
        } catch {
            return false
        }
    }

    /// Requests a widget-timeline reload with no accompanying store
    /// mutation - Phase 5's "reload triggers: app foreground" (see
    /// `AgendaViewModel.handleForeground()`). A foreground is not itself a
    /// mutation, but the widget's cached timeline is most likely stale right
    /// then (backgrounded overnight, a task completed elsewhere while away),
    /// so the app nudges a reload explicitly rather than relying only on
    /// WidgetKit's own reload budget.
    public func reloadWidgets() {
        widgetReloader.reloadAllTimelines()
    }

    // MARK: - Calendar visibility

    public func calendars() async throws -> [EventCalendarInfo] {
        try await calendarDirectory.calendars().map { info in
            EventCalendarInfo(
                identifier: info.identifier,
                title: info.title,
                colorRed: info.colorRed,
                colorGreen: info.colorGreen,
                colorBlue: info.colorBlue,
                isVisible: calendarVisibility.isVisible(calendarIdentifier: info.identifier)
            )
        }
    }

    public func setCalendarVisible(_ visible: Bool, calendarIdentifier: String) {
        calendarVisibility.setVisible(visible, calendarIdentifier: calendarIdentifier)
    }

    // MARK: - Private

    private func filterByCalendarVisibility(_ events: [Event]) -> [Event] {
        events.filter { calendarVisibility.isVisible(calendarIdentifier: $0.calendarIdentifier) }
    }
}

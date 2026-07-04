import Foundation

/// Which events are visible, by participation status. The two cases are named
/// after their surfaces: `.agenda` for the in-app schedule, `.widget` for the
/// Lock Screen.
public enum AgendaFilter: Equatable, Sendable {
    /// In-app agenda: everything except declined invitations. Pending
    /// (`needsAction`) invitations are kept - the UI marks them pending using
    /// the event's `participation` value; no separate flag is needed.
    case agenda
    /// Lock Screen: only events you are actually attending. Declined and pending
    /// (`needsAction`) invitations never render. Non-invite events you own
    /// (`.notInvited`) always render - excluding them would empty the widget.
    case widget

    /// Whether an event with `status` passes this filter.
    public func includes(_ status: ParticipationStatus) -> Bool {
        switch self {
        case .agenda:
            return status != .declined
        case .widget:
            switch status {
            case .accepted, .tentative, .notInvited:
                return true
            case .declined, .needsAction:
                return false
            }
        }
    }
}

/// A ready-to-render snapshot of one day (or window): the filtered, ordered
/// events and the incomplete task working set.
public struct AgendaSnapshot: Equatable, Sendable {
    /// Events passing the filter and the window, in display order (all-day
    /// first, then by start time, tie-broken by title then occurrence date).
    public let events: [Event]
    /// The incomplete working set: today's incomplete tasks plus rolled-over
    /// overdue incomplete tasks, deduplicated, ordered by due day then title.
    public let tasks: [DayTask]

    public init(events: [Event], tasks: [DayTask]) {
        self.events = events
        self.tasks = tasks
    }
}

/// Assemble the agenda for a window from raw store results. Pure: no I/O, no
/// clock, no globals. This single call hides interleave ordering, overdue
/// rollover, completed-task exclusion, garbled-item defense, and participation
/// filtering, so both the app and the widget produce identical agendas.
///
/// - Parameters:
///   - events: candidate events (any status, possibly outside the window or
///     garbled); filtered here.
///   - tasksDueToday: tasks whose due day is the window's day (any completion
///     state); completed ones are excluded here.
///   - overdueTasks: incomplete tasks from earlier days that roll forward.
///   - window: the day window; events must be members (see `DayWindow.contains`).
///   - filter: participation filter (`.agenda` or `.widget`).
public func assembleAgenda(
    events: [Event],
    tasksDueToday: [DayTask],
    overdueTasks: [DayTask],
    window: DayWindow,
    filter: AgendaFilter
) -> AgendaSnapshot {
    let visibleEvents = events
        .filter { $0.hasValidIdentifier }
        .filter { filter.includes($0.participation) }
        .filter { window.contains($0) }
        .sorted(by: eventOrdering)

    let workingTasks = mergeIncompleteTasks(tasksDueToday: tasksDueToday, overdueTasks: overdueTasks)
        .sorted(by: taskOrdering)

    return AgendaSnapshot(events: visibleEvents, tasks: workingTasks)
}

/// The incomplete working set shared by `assembleAgenda` and Feature 3's
/// badge count: today's incomplete tasks plus the overdue-incomplete
/// lookback, deduped by durable identifier (today and overdue are disjoint
/// by definition, but dedupe defensively), garbled items dropped. Pulled out
/// as its own pure function so the agenda's task list and the badge count
/// can never compute two different answers for the same store state -
/// unordered (callers that need display order, i.e. `assembleAgenda`, sort
/// the result themselves).
func mergeIncompleteTasks(tasksDueToday: [DayTask], overdueTasks: [DayTask]) -> [DayTask] {
    var seen = Set<String>()
    var workingTasks: [DayTask] = []
    for task in tasksDueToday + overdueTasks {
        guard task.hasValidIdentifier, !task.isCompleted else { continue }
        guard seen.insert(task.externalIdentifier).inserted else { continue }
        workingTasks.append(task)
    }
    return workingTasks
}

/// Feature 3: the icon-badge count is just the size of that same working
/// set - see `mergeIncompleteTasks`'s doc for why this can never drift from
/// what the agenda itself shows as incomplete.
public func incompleteTaskCount(tasksDueToday: [DayTask], overdueTasks: [DayTask]) -> Int {
    mergeIncompleteTasks(tasksDueToday: tasksDueToday, overdueTasks: overdueTasks).count
}

/// One day's Feature 2 month-view indicators: whether it has any visible
/// events (a dot, no count) and how many incomplete tasks are due that day
/// (a small count). Deliberately does not carry the events/tasks themselves -
/// Month view never needs more than these two facts per day; a day tap loads
/// the real `AgendaSnapshot` via the existing `agenda(for:filter:)` seam.
public struct DaySummary: Equatable, Sendable {
    public let hasEvents: Bool
    public let incompleteTaskCount: Int

    public init(hasEvents: Bool, incompleteTaskCount: Int) {
        self.hasEvents = hasEvents
        self.incompleteTaskCount = incompleteTaskCount
    }
}

/// Assemble a `[DayStamp: DaySummary]` for every civil day `window` covers,
/// from one whole-window events fetch and one whole-window incomplete-tasks
/// fetch. Pure - see `assembleAgenda`'s doc for why that matters (identical
/// output for app and any future caller, unit-testable with no I/O).
///
/// An event can span multiple civil days (multi-day all-day events, or a
/// timed event crossing midnight), so membership is tested per day via
/// `DayWindow.contains` rather than assigning each event to a single bucket -
/// see the Feature 2 design doc's rejected "pre-bucket by one key" alternative.
public func assembleMonthSummary(
    events: [Event],
    incompleteTasks: [DayTask],
    window: DayWindow,
    filter: AgendaFilter
) -> [DayStamp: DaySummary] {
    let visibleEvents = events
        .filter(\.hasValidIdentifier)
        .filter { filter.includes($0.participation) }
    let validTasks = incompleteTasks.filter(\.hasValidIdentifier)

    var result: [DayStamp: DaySummary] = [:]
    var instant = window.start
    while instant < window.end {
        let day = DayStamp(date: instant, calendar: window.calendar)
        guard let dayWindow = DayWindow(day: day, calendar: window.calendar) else { break }
        let hasEvents = visibleEvents.contains { dayWindow.contains($0) }
        let incompleteCount = validTasks.count { $0.dueDay == day }
        result[day] = DaySummary(hasEvents: hasEvents, incompleteTaskCount: incompleteCount)
        guard let next = window.calendar.date(byAdding: .day, value: 1, to: instant) else { break }
        instant = next
    }
    return result
}

/// Chronological interleave order: all-day events first (they have no meaningful
/// time), then timed events by start. Ties are broken deterministically by end,
/// title, then occurrence date so ordering is stable and testable.
private func eventOrdering(_ a: Event, _ b: Event) -> Bool {
    if a.isAllDay != b.isAllDay { return a.isAllDay }
    if a.start != b.start { return a.start < b.start }
    if a.end != b.end { return a.end < b.end }
    if a.title != b.title { return a.title < b.title }
    return a.occurrenceDate < b.occurrenceDate
}

/// Task order: by due day (older overdue first), then title, then identifier.
private func taskOrdering(_ a: DayTask, _ b: DayTask) -> Bool {
    if a.dueDay != b.dueDay { return a.dueDay < b.dueDay }
    if a.title != b.title { return a.title < b.title }
    return a.externalIdentifier < b.externalIdentifier
}

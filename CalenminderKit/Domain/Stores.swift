import Foundation

/// Which occurrences of a recurring series an edit or delete applies to.
public enum EditSpan: Equatable, Sendable {
    /// Only the single occurrence being edited.
    case thisEvent
    /// This occurrence and all future ones in the series.
    case futureEvents
}

/// The event side of the domain's storage seam. Phase 3 implements this over
/// EventKit; Phases 4/5 consume it. Defined in the domain (Clean Architecture:
/// the abstraction lives in the inner layer, the implementation in the outer).
///
/// `Task` in the plan's contract is spelled `DayTask` here to avoid colliding
/// with Swift concurrency's `Task`; the storage vocabulary is unchanged.
public protocol EventStoring {
    /// Coarse change signal: emits when the underlying store may have changed
    /// (e.g. republished `EKEventStoreChanged`). Consumers refetch the window.
    var changes: AsyncStream<Void> { get }

    func events(in window: DayWindow) async throws -> [Event]
    func create(_ draft: EventDraft) async throws -> Event
    /// `.thisEvent` | `.futureEvents`.
    func update(_ event: Event, span: EditSpan) async throws
    func delete(_ event: Event, span: EditSpan) async throws
}

/// The task side of the domain's storage seam. Phase 3 implements this over
/// EKReminders; Phases 4/5 consume it.
public protocol TaskStoring {
    /// Coarse change signal (see `EventStoring.changes`).
    var changes: AsyncStream<Void> { get }

    func tasks(dueOn day: DayStamp, includeCompleted: Bool) async throws -> [DayTask]
    /// Unbounded lookback for rollover display: all still-incomplete tasks whose
    /// due day is on or before `day`.
    func incompleteTasks(overdueAsOf day: DayStamp) async throws -> [DayTask]
    func add(_ draft: TaskDraft) async throws -> DayTask
    func setCompleted(_ task: DayTask, _ completed: Bool) async throws
}

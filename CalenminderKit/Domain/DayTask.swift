import Foundation

/// How a task repeats. v1 supports weekly-by-weekday ("every Monday"),
/// matching the recycling use case; daily ("every day") was added post-v1 for
/// the same reason -- EventKit honors one recurrence rule per reminder.
///
/// Named `TaskRecurrence` (not `Recurrence`) to stay unambiguous alongside
/// event recurrence, which the domain never expands (EventKit hands back
/// pre-expanded event occurrences).
public enum TaskRecurrence: Equatable, Sendable {
    /// Repeats weekly on `weekday`, using Gregorian weekday numbering
    /// (Sunday = 1 ... Saturday = 7), matching `Calendar.component(.weekday:)`.
    case weekly(weekday: Int)
    /// Repeats every day.
    case daily
}

/// A day-scoped, completable task - the domain view of an EKReminder.
///
/// Named `DayTask` rather than `Task` on purpose: `Task` collides with Swift
/// concurrency's `_Concurrency.Task` in every file that consumes this type
/// (the store, agenda, UI, and widget all use `Task {}` for async work). The
/// UI/API vocabulary stays "Task" (see `TaskStoring`, `TaskDraft`); only the
/// literal type spelling is disambiguated.
public struct DayTask: Equatable, Identifiable, Sendable {
    /// `calendarItemExternalIdentifier` of the underlying reminder - the durable
    /// cross-layer key, never a bare `id`.
    public let externalIdentifier: String
    public let title: String
    /// The civil day the task belongs to. No time component.
    public let dueDay: DayStamp
    public let isCompleted: Bool
    public let recurrence: TaskRecurrence?

    public init(
        externalIdentifier: String,
        title: String,
        dueDay: DayStamp,
        isCompleted: Bool,
        recurrence: TaskRecurrence? = nil
    ) {
        self.externalIdentifier = externalIdentifier
        self.title = title
        self.dueDay = dueDay
        self.isCompleted = isCompleted
        self.recurrence = recurrence
    }

    public var id: String { externalIdentifier }

    /// Whether this task carries a usable durable identifier. Tasks failing this
    /// are excluded from the agenda rather than crashing.
    public var hasValidIdentifier: Bool {
        !externalIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The mutable fields needed to create a new task. No identifier: the store
/// assigns it.
public struct TaskDraft: Equatable, Sendable {
    public var title: String
    public var dueDay: DayStamp
    public var recurrence: TaskRecurrence?

    public init(title: String, dueDay: DayStamp, recurrence: TaskRecurrence? = nil) {
        self.title = title
        self.dueDay = dueDay
        self.recurrence = recurrence
    }
}

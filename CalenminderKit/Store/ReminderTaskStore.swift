import Foundation
import EventKit

/// `TaskStoring` implemented over a dedicated EKReminders list. Public API
/// surface of this file is exactly `TaskStoring`'s five members.
///
/// **Reminder rollover -- empirically verified, no app-side fallback
/// needed** (see the Phase 3 design doc): the plan flagged as Medium
/// confidence whether completing a recurring `EKReminder` rolls to its next
/// occurrence system-side. Verified on the simulator's real Reminders store
/// (`ReminderTaskStoreIntegrationTests.test_DW_3_3_recurringReminderRolloverVerdict`):
/// **it does** -- `EKReminder.save(_:commit:)`, given a recurring reminder
/// with `isCompleted = true`, advances `dueDateComponents` to the next
/// occurrence and resets `isCompleted` to `false` on its own, in place, same
/// `calendarItemExternalIdentifier`. `setCompleted` therefore does nothing
/// recurrence-specific: it is a plain pass-through, and the plan's fallback
/// path (this store computing and writing the next occurrence itself) is
/// not needed -- doing so anyway would double-advance the due date.
public final class ReminderTaskStore: TaskStoring {
    /// The dedicated list this store reads and writes. Per code-standards,
    /// tasks live in one dedicated Reminders list -- never mixed with the
    /// user's other reminders.
    static let listName = "Calenminder Tasks"

    private let provider: ReminderProviding

    public var changes: AsyncStream<Void> { provider.changes }

    /// Production entry point: talks to the real system reminders store.
    public convenience init() {
        self.init(provider: SystemCalendarProvider())
    }

    /// Test/internal entry point: injects a fixture provider.
    init(provider: ReminderProviding) {
        self.provider = provider
    }

    public func tasks(dueOn day: DayStamp, includeCompleted: Bool) async throws -> [DayTask] {
        try await ensureAccess()
        let listID = try resolvedListID()
        return await provider.fetchReminders(calendarIdentifier: listID)
            .filter { Self.dayStamp(from: $0.dueDay) == day }
            .filter { includeCompleted || !$0.isCompleted }
            .map(Self.task(from:))
    }

    public func incompleteTasks(overdueAsOf day: DayStamp) async throws -> [DayTask] {
        try await ensureAccess()
        let listID = try resolvedListID()
        return await provider.fetchIncompleteReminders(calendarIdentifier: listID, dueOnOrBefore: Self.dateComponents(from: day))
            .filter { !$0.isCompleted }
            .map(Self.task(from:))
    }

    /// Feature 2's bounded month-range fetch. Reuses the *same* single
    /// provider call `tasks(dueOn:)` already makes (`fetchReminders(calendarIdentifier:)`
    /// - an unbounded-but-single "everything in this list" fetch), just
    /// filtered to a day range in memory instead of one day. No
    /// `ReminderProviding`/`FixtureCalendarProvider` change is needed: the
    /// provider seam already returns everything in one call, so a range
    /// filter costs nothing extra at the store layer.
    public func incompleteTasks(dueBetween start: DayStamp, and end: DayStamp) async throws -> [DayTask] {
        try await ensureAccess()
        let listID = try resolvedListID()
        return await provider.fetchReminders(calendarIdentifier: listID)
            .filter { !$0.isCompleted }
            .map(Self.task(from:))
            .filter { $0.dueDay >= start && $0.dueDay <= end }
    }

    public func add(_ draft: TaskDraft) async throws -> DayTask {
        try await ensureAccess()
        let listID = try resolvedListID()
        do {
            let rawDraft = RawReminderDraft(
                title: draft.title,
                dueDay: Self.dateComponents(from: draft.dueDay),
                recurrenceWeekday: Self.weekday(from: draft.recurrence),
                recurrenceIsDaily: Self.isDaily(from: draft.recurrence)
            )
            let record = try provider.createReminder(rawDraft, calendarIdentifier: listID)
            return Self.task(from: record)
        } catch {
            throw Self.mapError(error)
        }
    }

    public func setCompleted(_ task: DayTask, _ completed: Bool) async throws {
        try await ensureAccess()
        do {
            _ = try provider.setReminderCompleted(externalIdentifier: task.externalIdentifier, completed: completed)
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Access

    /// Reminders authorization has no write-only tier (unlike events): it is
    /// `.fullAccess` or nothing usable.
    private func ensureAccess() async throws {
        switch provider.reminderAuthorizationStatus() {
        case .fullAccess:
            return
        case .notDetermined:
            guard try await provider.requestFullAccessToReminders() else {
                throw CalendarStoreError.accessDenied(.reminder)
            }
        default:
            throw CalendarStoreError.accessDenied(.reminder)
        }
    }

    private func resolvedListID() throws -> String {
        do {
            return try provider.taskListCalendar(named: Self.listName)
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Mapping

    private static func dateComponents(from day: DayStamp) -> DateComponents {
        var c = DateComponents()
        c.year = day.year
        c.month = day.month
        c.day = day.day
        return c
    }

    private static func dayStamp(from components: DateComponents) -> DayStamp {
        DayStamp(year: components.year ?? 0, month: components.month ?? 0, day: components.day ?? 0)
    }

    private static func weekday(from recurrence: TaskRecurrence?) -> Int? {
        guard case .weekly(let weekday) = recurrence else { return nil }
        return weekday
    }

    private static func isDaily(from recurrence: TaskRecurrence?) -> Bool {
        guard case .daily = recurrence else { return false }
        return true
    }

    /// At most one of `recurrenceWeekday`/`recurrenceIsDaily` is ever set on
    /// a real record (see `RawReminderRecord`'s doc comment); weekday is
    /// checked first, matching how `SystemCalendarProvider.createReminder`
    /// prioritizes it when both happened to be present on a garbled record.
    private static func recurrence(from record: RawReminderRecord) -> TaskRecurrence? {
        if let weekday = record.recurrenceWeekday { return .weekly(weekday: weekday) }
        if record.recurrenceIsDaily { return .daily }
        return nil
    }

    private static func task(from record: RawReminderRecord) -> DayTask {
        DayTask(
            externalIdentifier: record.externalIdentifier,
            title: record.title,
            dueDay: dayStamp(from: record.dueDay),
            isCompleted: record.isCompleted,
            recurrence: recurrence(from: record)
        )
    }

    private static func mapError(_ error: Error) -> CalendarStoreError {
        if let calendarStoreError = error as? CalendarStoreError { return calendarStoreError }
        if let providerError = error as? ProviderError {
            switch providerError {
            case .itemNotFound: return .itemDeletedUnderneath
            case .underlying(let underlying): return .saveFailed(underlying: underlying)
            }
        }
        return .saveFailed(underlying: error)
    }
}

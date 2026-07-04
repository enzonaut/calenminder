import Foundation
import EventKit

/// The testable seam beneath `ReminderTaskStore`. See `EventProviding`'s
/// documentation for why this trades in `Raw*` DTOs rather than `EKReminder`
/// or raw predicates, and why it stays internal rather than public.
///
/// All reads are scoped to a single dedicated Reminders list, matching
/// `docs/code-standards.md` ("Tasks are EKReminders in a dedicated list; no
/// parallel local task store") -- `ReminderTaskStore` owns the policy of
/// which list that is and creates it if missing; this seam just operates
/// against whichever `EKCalendar` it is handed.
protocol ReminderProviding: AnyObject {
    var changes: AsyncStream<Void> { get }

    func requestFullAccessToReminders() async throws -> Bool
    func reminderAuthorizationStatus() -> EKAuthorizationStatus

    /// Finds the dedicated task list by name, creating it (on the default
    /// reminders source) if it does not exist yet.
    func taskListCalendar(named name: String) throws -> String

    /// All reminders in `calendarIdentifier`, regardless of due day or
    /// completion. Filtering by day/completion happens in `ReminderTaskStore`.
    func fetchReminders(calendarIdentifier: String) async -> [RawReminderRecord]

    /// Incomplete reminders in `calendarIdentifier` whose due day is on or
    /// before `day`, via `predicateForIncompleteReminders(withDueDateStarting:ending:)`
    /// -- the plan's mandated overdue-lookback predicate.
    func fetchIncompleteReminders(calendarIdentifier: String, dueOnOrBefore day: DateComponents) async -> [RawReminderRecord]

    func createReminder(_ draft: RawReminderDraft, calendarIdentifier: String) throws -> RawReminderRecord

    /// Sets completion and returns the resulting record. On a recurring
    /// reminder, EventKit itself advances `dueDateComponents` to the next
    /// occurrence and resets completion on save -- empirically verified (see
    /// the Phase 3 design doc); this seam does not need a separate
    /// reschedule operation for that.
    func setReminderCompleted(externalIdentifier: String, completed: Bool) throws -> RawReminderRecord
}

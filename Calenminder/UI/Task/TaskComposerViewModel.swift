import Foundation
import CalenminderKit

/// Form state for adding a new task. Reports through the injected
/// `AgendaViewModel` rather than calling `AgendaService` directly (same
/// reasoning as `EventEditViewModel`).
@MainActor
final class TaskComposerViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var dueDay: DayStamp
    /// Mutually exclusive with `repeatsDaily` -- setting one off the other,
    /// enforced here (not the view) so it holds regardless of which control
    /// drives it.
    @Published var repeatsWeekly: Bool = false {
        didSet { if repeatsWeekly && repeatsDaily { repeatsDaily = false } }
    }
    @Published var weekday: Int
    @Published var repeatsDaily: Bool = false {
        didSet { if repeatsDaily && repeatsWeekly { repeatsWeekly = false } }
    }
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let agenda: AgendaViewModel
    private let calendar: Calendar

    init(agenda: AgendaViewModel, dueDay: DayStamp, calendar: Calendar = .current) {
        self.agenda = agenda
        self.dueDay = dueDay
        self.calendar = calendar
        // Default the weekday picker to the due day's own weekday, so
        // "repeat weekly" defaults to "every day like this one".
        self.weekday = (dueDay.startOfDay(in: calendar)).map { calendar.component(.weekday, from: $0) } ?? 1
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Returns the created task on success (caller dismisses), `nil` on
    /// failure with `errorMessage` set.
    func save() async -> DayTask? {
        guard canSave else { return nil }
        isSaving = true
        defer { isSaving = false }

        // Determine the recurrence and the first-occurrence anchor day
        // together. For a weekly task the anchor must land on the selected
        // weekday, not on the day the task was composed: EventKit advances a
        // recurring reminder from its due-day anchor, so an anchor left on the
        // creation day (e.g. a Sunday) would surface the task on that wrong
        // day. Snapping to the next occurrence of `weekday` (same day counts,
        // so composing "every Monday" on a Monday keeps today) makes the task
        // first appear on its weekday. Daily needs no snap - "every day"
        // already includes the creation day - and a non-recurring task keeps
        // the exact day it was composed for.
        let recurrence: TaskRecurrence?
        let anchorDay: DayStamp
        if repeatsDaily {
            recurrence = .daily
            anchorDay = dueDay
        } else if repeatsWeekly {
            recurrence = .weekly(weekday: weekday)
            anchorDay = dueDay.nextOccurrence(ofWeekday: weekday, in: calendar) ?? dueDay
        } else {
            recurrence = nil
            anchorDay = dueDay
        }
        let draft = TaskDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDay: anchorDay,
            recurrence: recurrence
        )
        guard let created = await agenda.addTask(draft) else {
            errorMessage = agenda.errorMessage
            return nil
        }
        return created
    }
}

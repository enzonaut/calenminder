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

        let recurrence: TaskRecurrence? = repeatsDaily ? .daily : (repeatsWeekly ? .weekly(weekday: weekday) : nil)
        let draft = TaskDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDay: dueDay,
            recurrence: recurrence
        )
        guard let created = await agenda.addTask(draft) else {
            errorMessage = agenda.errorMessage
            return nil
        }
        return created
    }
}

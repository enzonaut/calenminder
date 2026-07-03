import Foundation
import CalenminderKit

/// Shared form state for both creating and editing an event; which mode it
/// is only changes what `save()` does. Reports its result back to the
/// injected `AgendaViewModel` (the sole owner of optimistic apply/rollback -
/// see the Phase 4 design doc) rather than calling `AgendaService` itself.
@MainActor
final class EventEditViewModel: ObservableObject {
    enum Mode {
        case create
        case edit(original: Event)
    }

    @Published var title: String
    @Published var start: Date
    @Published var end: Date
    @Published var isAllDay: Bool
    @Published var calendarIdentifier: String?
    @Published var span: EditSpan = .thisEvent
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    let mode: Mode
    private let agenda: AgendaViewModel

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    init(agenda: AgendaViewModel, mode: Mode) {
        self.agenda = agenda
        self.mode = mode
        switch mode {
        case .create:
            let now = Date()
            title = ""
            start = now
            end = now.addingTimeInterval(3600)
            isAllDay = false
            calendarIdentifier = nil
        case .edit(let event):
            title = event.title
            start = event.start
            end = event.end
            isAllDay = event.isAllDay
            calendarIdentifier = event.calendarIdentifier
        }
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && end >= start
    }

    /// Returns `true` on success (caller dismisses); `false` leaves the form
    /// state untouched with `errorMessage` set, so the user can retry
    /// without re-entering anything.
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create:
            let draft = EventDraft(title: trimmedTitle, start: start, end: end, isAllDay: isAllDay, calendarIdentifier: calendarIdentifier)
            guard let created = await agenda.createEvent(draft) else {
                errorMessage = agenda.errorMessage
                return false
            }
            _ = created
            return true
        case .edit(let original):
            let updated = Event(
                externalIdentifier: original.externalIdentifier,
                occurrenceDate: original.occurrenceDate,
                title: trimmedTitle,
                start: start,
                end: end,
                isAllDay: isAllDay,
                participation: original.participation,
                calendarIdentifier: calendarIdentifier ?? original.calendarIdentifier
            )
            let succeeded = await agenda.updateEvent(original, applying: updated, span: span)
            if !succeeded { errorMessage = agenda.errorMessage }
            return succeeded
        }
    }
}

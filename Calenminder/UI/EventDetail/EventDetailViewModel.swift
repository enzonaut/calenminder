import Foundation
import CalenminderKit

/// Loads and displays one event occurrence by identity - used both from an
/// agenda row tap and from an `event` deep link. Deliberately bypasses the
/// `.agenda` participation filter (via `AgendaService.resolveEvent`, not
/// `AgendaViewModel.snapshot`), so a declined invite is still viewable here
/// even though it never appears in the agenda list (code-standards: "declined
/// visible only on invite detail").
@MainActor
final class EventDetailViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case found(Event)
        case notFound
        case error(String)
    }

    @Published private(set) var state: State = .loading

    let externalIdentifier: String
    let occurrenceDate: Date

    private let agenda: AgendaViewModel

    init(agenda: AgendaViewModel, externalIdentifier: String, occurrenceDate: Date) {
        self.agenda = agenda
        self.externalIdentifier = externalIdentifier
        self.occurrenceDate = occurrenceDate
    }

    func load() async {
        state = .loading
        do {
            guard let event = try await agenda.resolveEvent(externalIdentifier: externalIdentifier, occurrenceDate: occurrenceDate) else {
                state = .notFound
                return
            }
            state = .found(event)
        } catch CalendarStoreError.itemDeletedUnderneath {
            state = .notFound
        } catch {
            state = .error(ErrorPresentation.message(for: error))
        }
    }

    /// `span` applies to both `.thisEvent` and `.futureEvents`; a
    /// non-recurring event treats either the same way (Phase 3's
    /// `EventKitEventStore` verified `.thisEvent` on a single event edits
    /// only it - `.futureEvents` on a single-occurrence event has the same
    /// effect since there is no series to extend into). The span picker is
    /// always shown rather than introducing a new "is this recurring" flag
    /// Domain does not expose.
    func delete(span: EditSpan) async -> Bool {
        guard case .found(let event) = state else { return false }
        let deleted = await agenda.deleteEvent(event, span: span)
        if deleted { state = .notFound }
        return deleted
    }
}

import Foundation
import CalenminderKit

/// Composition root: builds the one `AgendaService` the whole app shares.
/// A plain struct (not an `ObservableObject`) - it hands out a reference
/// type (`AgendaService`) that does not itself change, so nothing here needs
/// to be observable; the view models built from it own their own
/// `@Published` state.
struct AppEnvironment {
    let agendaService: AgendaService

    /// Production instance: real EventKit-backed stores.
    static func live() -> AppEnvironment {
        AppEnvironment(agendaService: AgendaService(
            eventStore: EventKitEventStore(),
            taskStore: ReminderTaskStore()
        ))
    }
}

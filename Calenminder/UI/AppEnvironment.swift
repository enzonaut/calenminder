import Foundation
import CalenminderKit

/// Composition root: builds the one `AgendaService` the whole app shares.
/// A plain struct (not an `ObservableObject`) - it hands out a reference
/// type (`AgendaService`) that does not itself change, so nothing here needs
/// to be observable; the view models built from it own their own
/// `@Published` state.
struct AppEnvironment {
    let agendaService: AgendaService
    /// Feature 3: shared badge orchestrator - built once here so
    /// `ContentView`'s lifecycle hooks and `BadgeRefreshScheduler` call the
    /// exact same instance, rather than each computing "today's count"
    /// independently.
    let badgeUpdater: BadgeUpdater

    /// Production instance: real EventKit-backed stores.
    static func live() -> AppEnvironment {
        let agendaService = AgendaService(
            eventStore: EventKitEventStore(),
            taskStore: ReminderTaskStore()
        )
        return AppEnvironment(agendaService: agendaService, badgeUpdater: BadgeUpdater(agendaService: agendaService))
    }
}

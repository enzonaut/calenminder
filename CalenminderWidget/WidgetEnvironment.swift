import Foundation
import CalenminderKit

/// Composition root for the widget extension process - mirrors
/// `Calenminder/UI/AppEnvironment.swift`'s `AgendaService` construction.
/// Duplicated rather than shared because `AppEnvironment` lives in the app
/// target (UI-only, per `docs/code-standards.md`'s dependency direction:
/// nothing imports `UI`) and the widget extension is a *separate process*
/// that needs its own instance regardless; both build the exact same
/// `AgendaService` type over the exact same real stores. Constructing a
/// fresh `AgendaService` per call (rather than caching one) is intentional
/// and matches `AgendaService`'s own documented design: it is stateless,
/// "equally correct for a long-lived app process and a widget process that
/// runs once per timeline entry."
enum WidgetEnvironment {
    static func liveAgendaService() -> AgendaService {
        AgendaService(eventStore: EventKitEventStore(), taskStore: ReminderTaskStore())
    }

    /// Feature 3: a `BadgeUpdater` over the given `agendaService` (pass the
    /// same instance `liveAgendaService()` just built, so the badge count
    /// and the completion it is reacting to are computed against the exact
    /// same stores). Built fresh per call, mirroring `liveAgendaService()`
    /// itself - see `BadgeUpdater`'s own doc comment on why that statelessness
    /// is fine for a process that runs once per intent invocation.
    static func liveBadgeUpdater(agendaService: AgendaService) -> BadgeUpdater {
        BadgeUpdater(agendaService: agendaService)
    }
}

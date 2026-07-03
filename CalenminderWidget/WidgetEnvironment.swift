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
}

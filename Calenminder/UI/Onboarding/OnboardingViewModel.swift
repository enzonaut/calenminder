import Foundation
import CalenminderKit

/// Gates the main agenda behind full Calendars + Reminders access. Rather
/// than a separate "check permission status" API, this probes by calling
/// the exact same read path the agenda needs (`AgendaService.agenda`):
/// EventKit's own store already requests access on first use when a status
/// is `.notDetermined` (see `EventKitEventStore.ensureReadAccess` /
/// `ReminderTaskStore.ensureAccess`), so one call both triggers the system
/// prompts (first launch) and tells us whether we can proceed (every
/// launch after) - no separate permission-status surface needed anywhere.
@MainActor
final class OnboardingViewModel: ObservableObject {
    enum State: Equatable {
        case checking
        case needsPermission(message: String)
        case granted
    }

    @Published private(set) var state: State = .checking

    private let agendaService: AgendaService
    private let calendar: Calendar

    init(agendaService: AgendaService, calendar: Calendar = .current) {
        self.agendaService = agendaService
        self.calendar = calendar
    }

    func start() async {
        state = .checking
        let today = DayStamp(date: Date(), calendar: calendar)
        guard let window = DayWindow(day: today, calendar: calendar) else {
            state = .needsPermission(message: "Something went wrong determining today's date.")
            return
        }
        do {
            _ = try await agendaService.agenda(for: window, filter: .agenda)
            state = .granted
        } catch {
            state = .needsPermission(message: ErrorPresentation.message(for: error))
        }
    }
}

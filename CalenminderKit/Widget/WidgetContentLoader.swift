import Foundation
import EventKit

/// Loads one civil day's agenda for the widget, through the exact same
/// pinned `AgendaService.agenda(for:filter:)` seam the app uses -
/// `AgendaFilter.widget` is what actually enforces DW-5.1's "declined,
/// needsAction, and completed items absent" (declined/needsAction excluded
/// by the filter; completed tasks excluded because `AgendaSnapshot.tasks`
/// is already the incomplete-only working set). This type's only job is
/// wiring that filter in and turning a thrown `CalendarStoreError` into the
/// widget's first-class `.unavailable` state (DW-5.4) - a widget process has
/// nowhere to present a thrown error or an error dialog, so nothing here
/// ever throws.
public enum WidgetContentLoader {
    // PSEUDOCODE: loadSnapshot(day:calendar:agendaService:)
    //   Build the DayWindow for `day` in `calendar`.
    //   If the window cannot be built (pathological calendar) -> .failure(.loadFailed).
    //   Call agendaService.agenda(for: window, filter: .widget).
    //   On success -> .success(snapshot).
    //   On thrown error -> .failure(reason(for: error)).

    /// Never throws: any failure becomes `.failure(WidgetUnavailableReason)`.
    public static func loadSnapshot(
        day: DayStamp,
        calendar: Calendar,
        agendaService: AgendaService
    ) async -> Result<AgendaSnapshot, WidgetUnavailableReason> {
        guard let window = DayWindow(day: day, calendar: calendar) else {
            return .failure(.loadFailed)
        }
        do {
            let snapshot = try await agendaService.agenda(for: window, filter: .widget)
            return .success(snapshot)
        } catch {
            return .failure(reason(for: error))
        }
    }

    /// Maps a thrown store error to the widget-visible reason. Only
    /// `CalendarStoreError` cases get a specific, actionable reason
    /// (matching `ErrorPresentation`'s recovery-route philosophy); anything
    /// else collapses to the generic `.loadFailed`.
    static func reason(for error: Error) -> WidgetUnavailableReason {
        guard let storeError = error as? CalendarStoreError else { return .loadFailed }
        switch storeError {
        case .accessDenied(let entityType):
            return entityType == .reminder ? .remindersAccessDenied : .calendarsAccessDenied
        case .writeOnlyAccess:
            // Write-only is an events-authorization tier only (Reminders has
            // no write-only tier); it blocks the read this loader needs.
            return .calendarsAccessDenied
        case .itemDeletedUnderneath, .saveFailed:
            return .loadFailed
        }
    }
}

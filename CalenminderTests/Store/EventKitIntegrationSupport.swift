import Foundation
import EventKit

/// Shared setup for the simulator-only integration suites (DW-3.2, DW-3.3):
/// a scratch `EKCalendar` to write into so tests never touch the user's real
/// default calendar/reminders list, and teardown that removes it again.
enum IntegrationSupport {
    static func makeTestEventCalendar(in store: EKEventStore, title: String) throws -> EKCalendar {
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = title
        guard let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        else {
            throw TestSetupError.noSourceAvailable
        }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    static func removeTestCalendar(_ calendar: EKCalendar, from store: EKEventStore) {
        try? store.removeCalendar(calendar, commit: true)
    }

    enum TestSetupError: Error {
        case noSourceAvailable
    }
}

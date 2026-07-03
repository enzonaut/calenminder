import Foundation
import EventKit
import CalenminderKit

/// One place that turns a thrown error into the string a view shows. Kept in
/// the UI layer (not `CalenminderKit`) since user-facing copy is a
/// presentation concern - `CalendarStoreError`'s cases already document their
/// recovery route, this just renders it as English.
enum ErrorPresentation {
    static func message(for error: Error) -> String {
        guard let storeError = error as? CalendarStoreError else {
            return error.localizedDescription
        }
        switch storeError {
        case .accessDenied(let entityType):
            let subject = entityType == .event ? "Calendars" : "Reminders"
            return "Calenminder needs access to \(subject). Open Settings to allow it."
        case .writeOnlyAccess:
            return "Calenminder has limited access and needs full access to continue. Open Settings to update it."
        case .itemDeletedUnderneath:
            return "That item was changed or deleted elsewhere."
        case .saveFailed:
            return "Couldn't save your change. Please try again."
        }
    }
}

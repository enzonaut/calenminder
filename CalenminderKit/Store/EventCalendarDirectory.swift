import Foundation
import EventKit

/// Enumerates the calendars available for the visibility-toggle UI. A small,
/// additive capability - not part of the pinned `EventStoring` seam (Phase 2),
/// which is day-window-scoped and has no "list calendars" member. Public
/// because it appears in `AgendaService`'s public initializer (a default
/// argument's type must be at least as visible as the initializer using it).
public protocol EventCalendarDirectory: AnyObject {
    /// All event calendars, in system order. `isVisible` is always `true`
    /// here - visibility is a user preference layered on top by
    /// `AgendaService`/`CalendarVisibilityStoring`, which this type knows
    /// nothing about.
    func calendars() async throws -> [EventCalendarInfo]
}

/// Production `EventCalendarDirectory`, backed directly by `EKEventStore`.
/// Deliberately not routed through `EventProviding`/`SystemCalendarProvider`:
/// calendar enumeration is a one-shot, read-only, side-effect-free query with
/// no draft/update/delete surface, so a second DTO-translation seam would be
/// pure ceremony for this one method.
public final class SystemEventCalendarDirectory: EventCalendarDirectory {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public func calendars() async throws -> [EventCalendarInfo] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw CalendarStoreError.accessDenied(.event)
        }
        return store.calendars(for: .event).map(Self.info(from:))
    }

    private static func info(from calendar: EKCalendar) -> EventCalendarInfo {
        let components = calendar.cgColor.flatMap { $0.components } ?? [0.5, 0.5, 0.5]
        // RGB(A) or grayscale color spaces both start with the color
        // channel(s) we care about; fall back to a neutral gray if the color
        // space is something unexpected (never crash on a system color).
        let red = components.first ?? 0.5
        let green = components.count > 2 ? components[1] : red
        let blue = components.count > 2 ? components[2] : red
        return EventCalendarInfo(
            identifier: calendar.calendarIdentifier,
            title: calendar.title,
            colorRed: Double(red),
            colorGreen: Double(green),
            colorBlue: Double(blue),
            isVisible: true
        )
    }
}

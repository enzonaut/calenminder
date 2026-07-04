import Foundation
import EventKit

/// Plain-Swift snapshot of one calendar event, as seen by the `EventProviding`
/// seam. Deliberately never `EKEvent`: `EKEvent` can only be constructed
/// against a real `EKEventStore`, and its durable
/// `calendarItemExternalIdentifier` is assigned by EventKit only after a real
/// `save()` -- it cannot be hand-seeded, so it cannot serve as a unit-test
/// fixture. This record can: it is seeded directly by
/// `FixtureCalendarProvider` in tests, and produced by translating a real
/// `EKEvent` inside `SystemCalendarProvider` in production.
///
/// `attendeeStatus`/`isOrganizer` are intentionally NOT pre-reduced to
/// `ParticipationStatus` here -- that mapping is domain logic and belongs in
/// `EventKitEventStore`, where it is testable against plain enum literals
/// with no EventKit store involved at all.
struct RawEventRecord: Equatable {
    var externalIdentifier: String
    var occurrenceDate: Date
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var attendeeStatus: EKParticipantStatus?
    var isOrganizer: Bool
    var calendarIdentifier: String
}

/// The mutable fields needed to create or update an event via the provider
/// seam. Mirrors `EventDraft` plus the fields `update` also needs to change.
struct RawEventDraft: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarIdentifier: String?
}

/// Plain-Swift snapshot of one reminder, as seen by the `ReminderProviding`
/// seam. Never `EKReminder`, for the same reason `RawEventRecord` is never
/// `EKEvent`.
///
/// `recurrenceWeekday`/`recurrenceIsDaily` are already reduced from
/// `EKReminder.recurrenceRules` down to "the first rule's weekday, if it is a
/// plain weekly-by-one-weekday rule" / "whether the first rule is a plain
/// daily rule" -- EventKit honors only one recurrence rule per reminder in
/// practice, and this app never writes more than one, so any additional rule
/// found on a reminder edited elsewhere is silently dropped here rather than
/// modeled. At most one of the two is ever non-empty (`recurrenceWeekday`
/// non-nil, or `recurrenceIsDaily` true) since a reminder carries one
/// recurrence rule of one shape.
struct RawReminderRecord: Equatable {
    var externalIdentifier: String
    var title: String
    /// Gregorian year/month/day only -- no time component.
    var dueDay: DateComponents
    var isCompleted: Bool
    var recurrenceWeekday: Int?
    var recurrenceIsDaily: Bool = false
}

/// The mutable fields needed to create a reminder via the provider seam.
struct RawReminderDraft: Equatable {
    var title: String
    var dueDay: DateComponents
    var recurrenceWeekday: Int?
    var recurrenceIsDaily: Bool = false
}

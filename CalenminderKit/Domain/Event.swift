import Foundation

/// Read-only participation (RSVP) status for a calendar event.
///
/// v1 never mutates this - EventKit's `participantStatus` is read-only and no
/// RSVP action exists anywhere in the app. Status is used only for display and
/// for the two agenda filters (see `AgendaFilter`).
public enum ParticipationStatus: Equatable, Sendable, CaseIterable {
    /// You accepted an invitation.
    case accepted
    /// You marked an invitation tentative / maybe.
    case tentative
    /// You declined an invitation.
    case declined
    /// A pending invitation you have not responded to (iCalendar NEEDS-ACTION).
    case needsAction
    /// Not an RSVP-bearing invite: an event you own or one with no attendees.
    /// Always visible (it is not an invite you could have declined).
    case notInvited
}

/// A durable, cross-layer reference to a specific event occurrence.
///
/// Per code standards, the durable key is `calendarItemExternalIdentifier` plus
/// the occurrence date - never a bare `eventIdentifier`, which can change when an
/// event moves between calendars. Recurring events share one external identifier
/// across occurrences, so the occurrence date disambiguates them.
public struct EventID: Hashable, Sendable {
    public let externalIdentifier: String
    public let occurrenceDate: Date

    public init(externalIdentifier: String, occurrenceDate: Date) {
        self.externalIdentifier = externalIdentifier
        self.occurrenceDate = occurrenceDate
    }
}

/// A canonical, time-sensitive calendar event - the domain view of an
/// EventKit occurrence, with no EventKit types leaking through.
public struct Event: Equatable, Identifiable, Sendable {
    /// `calendarItemExternalIdentifier` of the underlying calendar item.
    public let externalIdentifier: String
    /// Which occurrence this is (start of the occurrence), for recurring series.
    public let occurrenceDate: Date
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let participation: ParticipationStatus
    /// Identifier of the calendar this event belongs to (for visibility toggles).
    public let calendarIdentifier: String

    public init(
        externalIdentifier: String,
        occurrenceDate: Date,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        participation: ParticipationStatus,
        calendarIdentifier: String
    ) {
        self.externalIdentifier = externalIdentifier
        self.occurrenceDate = occurrenceDate
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.participation = participation
        self.calendarIdentifier = calendarIdentifier
    }

    public var id: EventID {
        EventID(externalIdentifier: externalIdentifier, occurrenceDate: occurrenceDate)
    }

    /// Whether this event carries a usable durable identifier. Events failing
    /// this (empty/blank external identifier) are excluded from the agenda
    /// rather than crashing - a garbled EventKit item must not break the day.
    public var hasValidIdentifier: Bool {
        !externalIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The mutable fields needed to create a new event. No identifiers: the store
/// assigns them. `calendarIdentifier == nil` means the user's default calendar.
public struct EventDraft: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarIdentifier: String?

    public init(
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarIdentifier: String? = nil
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarIdentifier = calendarIdentifier
    }
}

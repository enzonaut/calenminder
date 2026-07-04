import Foundation
import EventKit

/// `EventStoring` implemented over EventKit. Public API surface of this file
/// is exactly `EventStoring`'s five members -- every EventKit detail
/// (predicates, occurrence resolution, participation derivation, permission
/// state machine) is hidden behind `EventProviding`.
public final class EventKitEventStore: EventStoring {
    private let provider: EventProviding

    public var changes: AsyncStream<Void> { provider.changes }

    /// Production entry point: talks to the real system calendar store.
    public convenience init() {
        self.init(provider: SystemCalendarProvider())
    }

    /// Test/internal entry point: injects a fixture provider. Not public --
    /// `EventProviding` is an implementation detail, reached from tests only
    /// via `@testable import CalenminderKit`.
    init(provider: EventProviding) {
        self.provider = provider
    }

    public func events(in window: DayWindow) async throws -> [Event] {
        try await ensureReadAccess()
        provider.refreshSourcesIfNecessary()
        return provider.fetchEvents(start: window.start, end: window.end).map(Self.event(from:))
    }

    public func create(_ draft: EventDraft) async throws -> Event {
        try await ensureWriteAccess()
        do {
            let record = try provider.createEvent(Self.rawDraft(from: draft))
            return Self.event(from: record)
        } catch {
            throw Self.mapError(error)
        }
    }

    public func update(_ event: Event, span: EditSpan) async throws {
        try await ensureWriteAccess()
        do {
            _ = try provider.updateEvent(
                externalIdentifier: event.externalIdentifier,
                occurrenceDate: event.occurrenceDate,
                draft: Self.rawDraft(from: event),
                span: EKSpan(span)
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    public func delete(_ event: Event, span: EditSpan) async throws {
        try await ensureWriteAccess()
        do {
            try provider.deleteEvent(externalIdentifier: event.externalIdentifier, occurrenceDate: event.occurrenceDate, span: EKSpan(span))
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Access

    /// Read paths need `.fullAccess`: write-only access cannot query the
    /// store at all, so it surfaces as a distinct, actionable error rather
    /// than an empty (and misleading) result.
    private func ensureReadAccess() async throws {
        switch provider.eventAuthorizationStatus() {
        case .fullAccess:
            return
        case .writeOnly:
            throw CalendarStoreError.writeOnlyAccess
        case .notDetermined:
            guard try await provider.requestFullAccessToEvents() else {
                throw CalendarStoreError.accessDenied(.event)
            }
        default:
            throw CalendarStoreError.accessDenied(.event)
        }
    }

    /// Write paths only need write-only-or-better access.
    private func ensureWriteAccess() async throws {
        switch provider.eventAuthorizationStatus() {
        case .fullAccess, .writeOnly:
            return
        case .notDetermined:
            guard try await provider.requestFullAccessToEvents() else {
                throw CalendarStoreError.accessDenied(.event)
            }
        default:
            throw CalendarStoreError.accessDenied(.event)
        }
    }

    // MARK: - Mapping

    private static func rawDraft(from draft: EventDraft) -> RawEventDraft {
        RawEventDraft(title: draft.title, start: draft.start, end: draft.end, isAllDay: draft.isAllDay, calendarIdentifier: draft.calendarIdentifier)
    }

    private static func rawDraft(from event: Event) -> RawEventDraft {
        RawEventDraft(title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay, calendarIdentifier: event.calendarIdentifier)
    }

    private static func event(from record: RawEventRecord) -> Event {
        Event(
            externalIdentifier: record.externalIdentifier,
            occurrenceDate: record.occurrenceDate,
            title: record.title,
            start: record.start,
            end: record.end,
            isAllDay: record.isAllDay,
            participation: participation(attendeeStatus: record.attendeeStatus, isOrganizer: record.isOrganizer),
            calendarIdentifier: record.calendarIdentifier
        )
    }

    /// Pure -- unit-testable against plain `EKParticipantStatus` literals,
    /// no store involved. The organizer of an invite they sent (even one
    /// with attendees) is never something they could have "declined", so
    /// organizer status wins over any attendee record.
    static func participation(attendeeStatus: EKParticipantStatus?, isOrganizer: Bool) -> ParticipationStatus {
        guard !isOrganizer, let status = attendeeStatus else { return .notInvited }
        switch status {
        case .accepted: return .accepted
        case .tentative: return .tentative
        case .declined: return .declined
        case .pending: return .needsAction
        default: return .notInvited
        }
    }

    private static func mapError(_ error: Error) -> CalendarStoreError {
        if let calendarStoreError = error as? CalendarStoreError { return calendarStoreError }
        if let providerError = error as? ProviderError {
            switch providerError {
            case .itemNotFound: return .itemDeletedUnderneath
            case .underlying(let underlying): return .saveFailed(underlying: underlying)
            }
        }
        return .saveFailed(underlying: error)
    }
}

extension EKSpan {
    init(_ span: EditSpan) {
        switch span {
        case .thisEvent: self = .thisEvent
        case .futureEvents: self = .futureEvents
        }
    }
}

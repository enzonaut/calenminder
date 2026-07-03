import Testing
import Foundation
import EventKit
@testable import CalenminderKit

/// DW-3.1 (event half): day-window fetch and span edits against
/// `FixtureCalendarProvider`. DW-3.4 (event half): typed permission errors.
/// Plus dirty coverage beyond the DW floor (T-3.2-shaped): deleted-underneath
/// and save-failure mapping.
struct EventKitEventStoreTests {
    let cal = Fixture.calendar("America/New_York")

    // MARK: - DW-3.1: day-window fetch

    @Test("DW-3.1: events(in:) returns only records overlapping the window, mapped to Domain Event")
    func test_DW_3_1_eventsInWindow_fetchesAndMapsRecordsWithinWindow() async throws {
        let provider = FixtureCalendarProvider()
        let window = DayWindow(day: DayStamp(year: 2026, month: 7, day: 3), calendar: cal)!
        let inWindow = RawEventRecord(
            externalIdentifier: "in", occurrenceDate: Fixture.date(cal, 2026, 7, 3, 9),
            title: "In window", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10),
            isAllDay: false, attendeeStatus: .accepted, isOrganizer: false, calendarIdentifier: "cal-1"
        )
        let outOfWindow = RawEventRecord(
            externalIdentifier: "out", occurrenceDate: Fixture.date(cal, 2026, 7, 5, 9),
            title: "Out of window", start: Fixture.date(cal, 2026, 7, 5, 9), end: Fixture.date(cal, 2026, 7, 5, 10),
            isAllDay: false, attendeeStatus: nil, isOrganizer: true, calendarIdentifier: "cal-1"
        )
        provider.events = [inWindow, outOfWindow]
        let store = EventKitEventStore(provider: provider)

        let events = try await store.events(in: window)

        #expect(events.map(\.externalIdentifier) == ["in"])
        #expect(events.first?.title == "In window")
        #expect(events.first?.participation == .accepted)
    }

    @Test("DW-3.1: events(in:) triggers a source refresh before fetching")
    func test_DW_3_1_eventsInWindow_refreshesSourcesFirst() async throws {
        let provider = FixtureCalendarProvider()
        let window = DayWindow(day: DayStamp(year: 2026, month: 7, day: 3), calendar: cal)!
        let store = EventKitEventStore(provider: provider)

        _ = try await store.events(in: window)

        #expect(provider.refreshCallCount == 1)
    }

    // MARK: - DW-3.1: create

    @Test("DW-3.1: create(_:) round-trips the draft's fields through a Domain Event")
    func test_DW_3_1_create_roundTripsDraftFields() async throws {
        let provider = FixtureCalendarProvider()
        let store = EventKitEventStore(provider: provider)
        let draft = EventDraft(
            title: "Standup", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 9, 30),
            isAllDay: false
        )

        let event = try await store.create(draft)

        #expect(event.title == "Standup")
        #expect(event.hasValidIdentifier)
        #expect(provider.events.count == 1)
    }

    // MARK: - DW-3.1: span edits (unit-level: verifies EventKitEventStore's
    // resolve-then-save call shape; the real system store's detached-
    // occurrence guarantee is DW-3.2, integration-only.)

    @Test("DW-3.1: update(span: .thisEvent) changes only the anchor occurrence")
    func test_DW_3_1_update_thisEventSpanUpdatesOnlyAnchorOccurrence() async throws {
        let provider = FixtureCalendarProvider()
        let seriesID = "series-1"
        let week1 = Fixture.date(cal, 2026, 7, 6, 9)
        let week2 = Fixture.date(cal, 2026, 7, 13, 9)
        provider.events = [
            RawEventRecord(externalIdentifier: seriesID, occurrenceDate: week1, title: "Standup", start: week1, end: week1.addingTimeInterval(1800), isAllDay: false, attendeeStatus: nil, isOrganizer: true, calendarIdentifier: "cal-1"),
            RawEventRecord(externalIdentifier: seriesID, occurrenceDate: week2, title: "Standup", start: week2, end: week2.addingTimeInterval(1800), isAllDay: false, attendeeStatus: nil, isOrganizer: true, calendarIdentifier: "cal-1"),
        ]
        let store = EventKitEventStore(provider: provider)
        let anchor = Event(externalIdentifier: seriesID, occurrenceDate: week1, title: "Standup (moved room)", start: week1, end: week1.addingTimeInterval(1800), isAllDay: false, participation: .notInvited, calendarIdentifier: "cal-1")

        try await store.update(anchor, span: .thisEvent)

        #expect(provider.events.first(where: { $0.occurrenceDate == week1 })?.title == "Standup (moved room)")
        #expect(provider.events.first(where: { $0.occurrenceDate == week2 })?.title == "Standup")
    }

    @Test("DW-3.1: update(span: .futureEvents) changes the anchor and every later occurrence, not earlier ones")
    func test_DW_3_1_update_futureEventsSpanUpdatesAnchorAndLaterOccurrences() async throws {
        let provider = FixtureCalendarProvider()
        let seriesID = "series-2"
        let past = Fixture.date(cal, 2026, 6, 29, 9)
        let anchorDate = Fixture.date(cal, 2026, 7, 6, 9)
        let future = Fixture.date(cal, 2026, 7, 13, 9)
        provider.events = [past, anchorDate, future].map {
            RawEventRecord(externalIdentifier: seriesID, occurrenceDate: $0, title: "Standup", start: $0, end: $0.addingTimeInterval(1800), isAllDay: false, attendeeStatus: nil, isOrganizer: true, calendarIdentifier: "cal-1")
        }
        let store = EventKitEventStore(provider: provider)
        let anchor = Event(externalIdentifier: seriesID, occurrenceDate: anchorDate, title: "Renamed", start: anchorDate, end: anchorDate.addingTimeInterval(1800), isAllDay: false, participation: .notInvited, calendarIdentifier: "cal-1")

        try await store.update(anchor, span: .futureEvents)

        #expect(provider.events.first(where: { $0.occurrenceDate == past })?.title == "Standup")
        #expect(provider.events.first(where: { $0.occurrenceDate == anchorDate })?.title == "Renamed")
        #expect(provider.events.first(where: { $0.occurrenceDate == future })?.title == "Renamed")
    }

    @Test("DW-3.1: delete(span: .thisEvent) removes only the anchor occurrence")
    func test_DW_3_1_delete_thisEventSpanRemovesOnlyAnchorOccurrence() async throws {
        let provider = FixtureCalendarProvider()
        let seriesID = "series-3"
        let week1 = Fixture.date(cal, 2026, 7, 6, 9)
        let week2 = Fixture.date(cal, 2026, 7, 13, 9)
        provider.events = [week1, week2].map {
            RawEventRecord(externalIdentifier: seriesID, occurrenceDate: $0, title: "Standup", start: $0, end: $0.addingTimeInterval(1800), isAllDay: false, attendeeStatus: nil, isOrganizer: true, calendarIdentifier: "cal-1")
        }
        let store = EventKitEventStore(provider: provider)
        let anchor = Event(externalIdentifier: seriesID, occurrenceDate: week1, title: "Standup", start: week1, end: week1.addingTimeInterval(1800), isAllDay: false, participation: .notInvited, calendarIdentifier: "cal-1")

        try await store.delete(anchor, span: .thisEvent)

        #expect(provider.events.count == 1)
        #expect(provider.events.first?.occurrenceDate == week2)
    }

    // MARK: - DW-3.4: typed permission errors

    @Test("DW-3.4: events(in:) with denied access throws .accessDenied(.event)")
    func test_DW_3_4_eventsInWindow_deniedThrowsAccessDenied() async throws {
        let provider = FixtureCalendarProvider()
        provider.eventAuthStatus = .denied
        let store = EventKitEventStore(provider: provider)
        let window = DayWindow(day: DayStamp(year: 2026, month: 7, day: 3), calendar: cal)!

        do {
            _ = try await store.events(in: window)
            Issue.record("expected accessDenied")
        } catch CalendarStoreError.accessDenied(let type) {
            #expect(type == .event)
        }
    }

    @Test("DW-3.4: events(in:) with write-only access throws .writeOnlyAccess (cannot read)")
    func test_DW_3_4_eventsInWindow_writeOnlyThrowsWriteOnlyAccess() async throws {
        let provider = FixtureCalendarProvider()
        provider.eventAuthStatus = .writeOnly
        let store = EventKitEventStore(provider: provider)
        let window = DayWindow(day: DayStamp(year: 2026, month: 7, day: 3), calendar: cal)!

        do {
            _ = try await store.events(in: window)
            Issue.record("expected writeOnlyAccess")
        } catch CalendarStoreError.writeOnlyAccess {
            // expected
        }
    }

    @Test("DW-3.4: create(_:) succeeds with write-only access (writing doesn't need full access)")
    func test_DW_3_4_create_writeOnlyAccessIsSufficient() async throws {
        let provider = FixtureCalendarProvider()
        provider.eventAuthStatus = .writeOnly
        let store = EventKitEventStore(provider: provider)

        let event = try await store.create(EventDraft(title: "T", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10), isAllDay: false))
        #expect(event.title == "T")
    }

    @Test("DW-3.4: notDetermined requests access and throws .accessDenied(.event) if the user declines")
    func test_DW_3_4_notDetermined_deniedRequestThrowsAccessDenied() async throws {
        let provider = FixtureCalendarProvider()
        provider.eventAuthStatus = .notDetermined
        provider.requestAccessGranted = false
        let store = EventKitEventStore(provider: provider)
        let window = DayWindow(day: DayStamp(year: 2026, month: 7, day: 3), calendar: cal)!

        do {
            _ = try await store.events(in: window)
            Issue.record("expected accessDenied")
        } catch CalendarStoreError.accessDenied(let type) {
            #expect(type == .event)
        }
    }

    // MARK: - Dirty coverage beyond the DW floor

    @Test("update(_:span:) on a since-deleted occurrence throws .itemDeletedUnderneath")
    func updateOnDeletedOccurrenceThrowsItemDeletedUnderneath() async throws {
        let provider = FixtureCalendarProvider()
        let store = EventKitEventStore(provider: provider)
        let ghost = Event(externalIdentifier: "gone", occurrenceDate: Fixture.date(cal, 2026, 7, 3, 9), title: "Gone", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10), isAllDay: false, participation: .notInvited, calendarIdentifier: "cal-1")

        do {
            try await store.update(ghost, span: .thisEvent)
            Issue.record("expected itemDeletedUnderneath")
        } catch CalendarStoreError.itemDeletedUnderneath {
            // expected
        }
    }

    @Test("create(_:) wraps a provider save failure as .saveFailed")
    func createWrapsSaveFailureAsSaveFailed() async throws {
        let provider = FixtureCalendarProvider()
        provider.forcedSaveError = CocoaError(.fileWriteUnknown)
        let store = EventKitEventStore(provider: provider)

        do {
            _ = try await store.create(EventDraft(title: "T", start: Fixture.date(cal, 2026, 7, 3, 9), end: Fixture.date(cal, 2026, 7, 3, 10), isAllDay: false))
            Issue.record("expected saveFailed")
        } catch CalendarStoreError.saveFailed {
            // expected
        }
    }

    // MARK: - Participation mapping (pure, no store)

    @Test("participation mapping: organizer is always notInvited, even with an attendee record")
    func participationMapping_organizerIsAlwaysNotInvited() {
        #expect(EventKitEventStore.participation(attendeeStatus: .accepted, isOrganizer: true) == .notInvited)
    }

    @Test("participation mapping: no attendee record is notInvited")
    func participationMapping_noAttendeeIsNotInvited() {
        #expect(EventKitEventStore.participation(attendeeStatus: nil, isOrganizer: false) == .notInvited)
    }

    @Test("participation mapping: every EKParticipantStatus maps to the documented ParticipationStatus", arguments: [
        (EKParticipantStatus.accepted, ParticipationStatus.accepted),
        (EKParticipantStatus.tentative, ParticipationStatus.tentative),
        (EKParticipantStatus.declined, ParticipationStatus.declined),
        (EKParticipantStatus.pending, ParticipationStatus.needsAction),
        (EKParticipantStatus.unknown, ParticipationStatus.notInvited),
    ])
    func participationMapping_statusTable(status: EKParticipantStatus, expected: ParticipationStatus) {
        #expect(EventKitEventStore.participation(attendeeStatus: status, isOrganizer: false) == expected)
    }
}

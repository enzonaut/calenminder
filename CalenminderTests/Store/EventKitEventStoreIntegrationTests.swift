import Testing
import Foundation
import EventKit
@testable import CalenminderKit

/// DW-3.2: recurring edit spans and detached occurrences, against the
/// simulator's real Calendars store. Simulator-only, serialized (see
/// `StoreTestTags.swift`); excluded from `make test`, run via
/// `make test-integration`. Requires Calendars full access already granted
/// to the test bundle (`xcrun simctl privacy <udid> grant calendar
/// com.enzonaut.calenminder.tests`, per the plan's Notes).
@Suite(.tags(.eventKitIntegration), .serialized)
struct EventKitEventStoreIntegrationTests {
    /// A weekday far enough in the future that "next matching weekday" never
    /// lands on a date that's already passed mid-test-run, with three
    /// weekly occurrences comfortably inside a 30-day query window.
    private func nextMonday(from now: Date = Date(), calendar: Calendar) -> Date {
        var start = calendar.date(byAdding: .day, value: 7, to: now)!
        while calendar.component(.weekday, from: start) != 2 {
            start = calendar.date(byAdding: .day, value: 1, to: start)!
        }
        var c = calendar.dateComponents([.year, .month, .day], from: start)
        c.hour = 9
        return calendar.date(from: c)!
    }

    @Test("DW-3.2: a .futureEvents series edit does not clobber a .thisEvent-detached occurrence")
    func test_DW_3_2_seriesEditDoesNotClobberDetachedOccurrence() async throws {
        let realStore = EKEventStore()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            Issue.record("Calendars full access not granted to the test runner -- run: xcrun simctl privacy <udid> grant calendar \(Bundle.main.bundleIdentifier ?? "com.enzonaut.calenminder.tests")")
            return
        }
        let calendar = Calendar(identifier: .gregorian)
        let testCalendar = try IntegrationSupport.makeTestEventCalendar(in: realStore, title: "Calenminder Test DW-3.2 \(UUID().uuidString.prefix(8))")
        defer { IntegrationSupport.removeTestCalendar(testCalendar, from: realStore) }

        // 1. Seed a weekly recurring event directly (EventDraft has no
        // recurrence field -- v1 never creates recurring *events* through
        // the app, only recurring *tasks* -- so recurring series are always
        // pre-existing data this store must edit correctly, not data it
        // creates itself).
        let start0 = nextMonday(from: Date(), calendar: calendar)
        let seriesEvent = EKEvent(eventStore: realStore)
        seriesEvent.title = "Standup"
        seriesEvent.startDate = start0
        seriesEvent.endDate = start0.addingTimeInterval(1800)
        seriesEvent.calendar = testCalendar
        seriesEvent.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))
        try realStore.save(seriesEvent, span: .futureEvents, commit: true)
        let externalID = try #require(seriesEvent.calendarItemExternalIdentifier)

        // 2. Resolve the first three occurrences.
        let windowEnd = calendar.date(byAdding: .day, value: 28, to: start0)!
        let predicate = realStore.predicateForEvents(withStart: start0.addingTimeInterval(-1), end: windowEnd, calendars: [testCalendar])
        let occurrences = realStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        #expect(occurrences.count >= 3)
        let occ0 = occurrences[0].startDate!
        let occ1 = occurrences[1].startDate!
        let occ2 = occurrences[2].startDate!

        let store = EventKitEventStore(provider: SystemCalendarProvider(store: realStore))

        // 3. Detach the middle occurrence with its own title.
        try await store.update(
            Event(externalIdentifier: externalID, occurrenceDate: occ1, title: "Standup (detached room)", start: occ1, end: occ1.addingTimeInterval(1800), isAllDay: false, participation: .notInvited, calendarIdentifier: testCalendar.calendarIdentifier),
            span: .thisEvent
        )

        // 4. Rename the series from the first occurrence forward.
        try await store.update(
            Event(externalIdentifier: externalID, occurrenceDate: occ0, title: "Standup (renamed series)", start: occ0, end: occ0.addingTimeInterval(1800), isAllDay: false, participation: .notInvited, calendarIdentifier: testCalendar.calendarIdentifier),
            span: .futureEvents
        )

        // 5. The detached occurrence must survive the series-wide rename;
        // the others must have picked it up.
        let afterPredicate = realStore.predicateForEvents(withStart: start0.addingTimeInterval(-1), end: windowEnd, calendars: [testCalendar])
        let after = realStore.events(matching: afterPredicate).sorted { $0.startDate < $1.startDate }
        let titleAt: (Date) -> String? = { date in after.first { abs($0.startDate.timeIntervalSince(date)) < 1 }?.title }

        #expect(titleAt(occ0) == "Standup (renamed series)")
        #expect(titleAt(occ1) == "Standup (detached room)")
        #expect(titleAt(occ2) == "Standup (renamed series)")

        // Cleanup: remove the whole series.
        if let toRemove = realStore.calendarItems(withExternalIdentifier: externalID).first as? EKEvent {
            try? realStore.remove(toRemove, span: .futureEvents, commit: true)
        }
    }

    @Test("DW-3.2: update(span: .thisEvent) on a non-recurring event edits only that event")
    func test_DW_3_2_thisEventSpanOnSingleEventEditsIt() async throws {
        let realStore = EKEventStore()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            Issue.record("Calendars full access not granted to the test runner")
            return
        }
        let testCalendar = try IntegrationSupport.makeTestEventCalendar(in: realStore, title: "Calenminder Test DW-3.2b \(UUID().uuidString.prefix(8))")
        defer { IntegrationSupport.removeTestCalendar(testCalendar, from: realStore) }

        let store = EventKitEventStore(provider: SystemCalendarProvider(store: realStore))
        let start = Date().addingTimeInterval(3600)
        let created = try await store.create(EventDraft(title: "Once", start: start, end: start.addingTimeInterval(1800), isAllDay: false, calendarIdentifier: testCalendar.calendarIdentifier))

        try await store.update(
            Event(externalIdentifier: created.externalIdentifier, occurrenceDate: created.occurrenceDate, title: "Once (renamed)", start: created.start, end: created.end, isAllDay: false, participation: .notInvited, calendarIdentifier: testCalendar.calendarIdentifier),
            span: .thisEvent
        )

        let window = DayWindow(start: start.addingTimeInterval(-3600), end: start.addingTimeInterval(7200), calendar: Calendar(identifier: .gregorian))
        let events = try await store.events(in: window)
        #expect(events.first(where: { $0.externalIdentifier == created.externalIdentifier })?.title == "Once (renamed)")
    }
}

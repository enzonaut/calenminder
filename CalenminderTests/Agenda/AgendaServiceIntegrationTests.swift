import Testing
import Foundation
import EventKit
@testable import CalenminderKit

/// DW-4.2: full flows verified on simulator, exercised through
/// `AgendaService` (the actual production call path the app and, from Phase
/// 5, the widget use) against the real Calendars/Reminders stores - not a
/// separate XCUITest driving the SwiftUI UI. See the Phase 4 discovery doc's
/// "Gaps" section for why this is the chosen strategy: the plan's own Test
/// Plan classifies this DW as "Integration (simulator)", which this
/// satisfies using the same tagging/serialization Phase 3 established.
/// Simulator-only, serialized; excluded from `make test`, run via
/// `make test-integration`.
@Suite(.tags(.eventKitIntegration), .serialized)
struct AgendaServiceIntegrationTests {
    private func nextMonday(from now: Date, calendar: Calendar) -> Date {
        var start = calendar.date(byAdding: .day, value: 7, to: now)!
        while calendar.component(.weekday, from: start) != 2 {
            start = calendar.date(byAdding: .day, value: 1, to: start)!
        }
        return start
    }

    private func scratchVisibilityStore() -> CalendarVisibilityStore {
        CalendarVisibilityStore(defaults: UserDefaults(suiteName: "AgendaServiceIntegrationTests.\(UUID().uuidString)")!)
    }

    @Test("DW-4.2: create, edit (.thisEvent), and delete an event through AgendaService")
    func test_DW_4_2_createEditDeleteEventThisEventSpan() async throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            Issue.record("Calendars full access not granted to the test runner")
            return
        }
        let realStore = EKEventStore()
        let calendar = Calendar(identifier: .gregorian)
        let testCalendar = try IntegrationSupport.makeTestEventCalendar(in: realStore, title: "Calenminder AgendaService DW-4.2 \(UUID().uuidString.prefix(8))")
        defer { IntegrationSupport.removeTestCalendar(testCalendar, from: realStore) }

        let eventStore = EventKitEventStore(provider: SystemCalendarProvider(store: realStore))
        let service = AgendaService(eventStore: eventStore, taskStore: ReminderTaskStore(), calendarVisibility: scratchVisibilityStore())

        let start = Date().addingTimeInterval(3600)
        let created = try await service.createEvent(EventDraft(title: "Coffee", start: start, end: start.addingTimeInterval(1800), isAllDay: false, calendarIdentifier: testCalendar.calendarIdentifier))

        let window = DayWindow(start: start.addingTimeInterval(-3600), end: start.addingTimeInterval(7200), calendar: calendar)
        let afterCreate = try await service.agenda(for: window, filter: .agenda)
        #expect(afterCreate.events.first(where: { $0.externalIdentifier == created.externalIdentifier })?.title == "Coffee")

        let edited = Event(externalIdentifier: created.externalIdentifier, occurrenceDate: created.occurrenceDate, title: "Coffee (renamed)", start: created.start, end: created.end, isAllDay: false, participation: .notInvited, calendarIdentifier: testCalendar.calendarIdentifier)
        try await service.updateEvent(edited, span: .thisEvent)

        let afterEdit = try await service.agenda(for: window, filter: .agenda)
        #expect(afterEdit.events.first(where: { $0.externalIdentifier == created.externalIdentifier })?.title == "Coffee (renamed)")

        try await service.deleteEvent(edited, span: .thisEvent)

        let afterDelete = try await service.agenda(for: window, filter: .agenda)
        #expect(afterDelete.events.first(where: { $0.externalIdentifier == created.externalIdentifier }) == nil)
    }

    @Test("DW-4.2: editing a recurring series with .futureEvents preserves a .thisEvent-detached occurrence")
    func test_DW_4_2_editEventFutureEventsSpan() async throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            Issue.record("Calendars full access not granted to the test runner")
            return
        }
        let realStore = EKEventStore()
        let calendar = Calendar(identifier: .gregorian)
        let testCalendar = try IntegrationSupport.makeTestEventCalendar(in: realStore, title: "Calenminder AgendaService DW-4.2b \(UUID().uuidString.prefix(8))")
        defer { IntegrationSupport.removeTestCalendar(testCalendar, from: realStore) }

        let start0 = nextMonday(from: Date(), calendar: calendar)
        let seriesEvent = EKEvent(eventStore: realStore)
        seriesEvent.title = "Standup"
        seriesEvent.startDate = start0
        seriesEvent.endDate = start0.addingTimeInterval(1800)
        seriesEvent.calendar = testCalendar
        seriesEvent.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))
        try realStore.save(seriesEvent, span: .futureEvents, commit: true)
        let externalID = try #require(seriesEvent.calendarItemExternalIdentifier)
        defer {
            if let toRemove = realStore.calendarItems(withExternalIdentifier: externalID).first as? EKEvent {
                try? realStore.remove(toRemove, span: .futureEvents, commit: true)
            }
        }

        let windowEnd = calendar.date(byAdding: .day, value: 21, to: start0)!
        let predicate = realStore.predicateForEvents(withStart: start0.addingTimeInterval(-1), end: windowEnd, calendars: [testCalendar])
        let occurrences = realStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        #expect(occurrences.count >= 2)
        let occ0 = occurrences[0].startDate!
        let occ1 = occurrences[1].startDate!

        let eventStore = EventKitEventStore(provider: SystemCalendarProvider(store: realStore))
        let service = AgendaService(eventStore: eventStore, taskStore: ReminderTaskStore(), calendarVisibility: scratchVisibilityStore())

        // Detach occurrence 1 with its own title, then rename the series
        // from occurrence 0 forward via AgendaService, mirroring how the app
        // itself would call these two mutations.
        try await service.updateEvent(
            Event(externalIdentifier: externalID, occurrenceDate: occ1, title: "Standup (detached)", start: occ1, end: occ1.addingTimeInterval(1800), isAllDay: false, participation: .notInvited, calendarIdentifier: testCalendar.calendarIdentifier),
            span: .thisEvent
        )
        try await service.updateEvent(
            Event(externalIdentifier: externalID, occurrenceDate: occ0, title: "Standup (renamed series)", start: occ0, end: occ0.addingTimeInterval(1800), isAllDay: false, participation: .notInvited, calendarIdentifier: testCalendar.calendarIdentifier),
            span: .futureEvents
        )

        let window = DayWindow(start: start0.addingTimeInterval(-3600), end: windowEnd, calendar: calendar)
        let after = try await service.agenda(for: window, filter: .agenda)
        let titleAt: (Date) -> String? = { date in after.events.first { abs($0.start.timeIntervalSince(date)) < 1 }?.title }
        #expect(titleAt(occ0) == "Standup (renamed series)")
        #expect(titleAt(occ1) == "Standup (detached)")
    }

    @Test("DW-4.2: create and complete a weekly-recurring task through AgendaService")
    func test_DW_4_2_createAndCompleteRecurringTask() async throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            Issue.record("Reminders full access not granted to the test runner")
            return
        }
        let calendar = Calendar(identifier: .gregorian)
        let dueDate = nextMonday(from: Date(), calendar: calendar)
        let dueDay = DayStamp(date: dueDate, calendar: calendar)
        let service = AgendaService(eventStore: EventKitEventStore(), taskStore: ReminderTaskStore(), calendarVisibility: scratchVisibilityStore())
        let title = "Calenminder AgendaService DW-4.2 task \(UUID().uuidString.prefix(8))"

        let created = try await service.addTask(TaskDraft(title: title, dueDay: dueDay, recurrence: .weekly(weekday: 2)))
        #expect(created.recurrence == .weekly(weekday: 2))

        let window = DayWindow(day: dueDay, calendar: calendar)!
        let beforeComplete = try await service.agenda(for: window, filter: .agenda)
        #expect(beforeComplete.tasks.contains(where: { $0.externalIdentifier == created.externalIdentifier }))

        try await service.setTaskCompleted(created, true)

        let afterComplete = try await service.agenda(for: window, filter: .agenda)
        #expect(!afterComplete.tasks.contains(where: { $0.externalIdentifier == created.externalIdentifier }), "completing rolls the recurring task off today's due day")

        // Cleanup: resolve the (now-rolled) reminder and remove it directly.
        let realStore = EKEventStore()
        if let reminder = realStore.calendarItems(withExternalIdentifier: created.externalIdentifier).first as? EKReminder {
            try? realStore.remove(reminder, commit: true)
        }
    }

    @Test("DW-4.2: hiding a calendar removes its events from agenda(for:filter:) without deleting them")
    func test_DW_4_2_calendarVisibilityToggleHidesEventsFromAgenda() async throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            Issue.record("Calendars full access not granted to the test runner")
            return
        }
        let realStore = EKEventStore()
        let calendar = Calendar(identifier: .gregorian)
        let testCalendar = try IntegrationSupport.makeTestEventCalendar(in: realStore, title: "Calenminder AgendaService DW-4.2c \(UUID().uuidString.prefix(8))")
        defer { IntegrationSupport.removeTestCalendar(testCalendar, from: realStore) }

        let eventStore = EventKitEventStore(provider: SystemCalendarProvider(store: realStore))
        let visibility = scratchVisibilityStore()
        let service = AgendaService(eventStore: eventStore, taskStore: ReminderTaskStore(), calendarVisibility: visibility)

        let start = Date().addingTimeInterval(3600)
        let created = try await service.createEvent(EventDraft(title: "Toggle Test", start: start, end: start.addingTimeInterval(1800), isAllDay: false, calendarIdentifier: testCalendar.calendarIdentifier))
        let window = DayWindow(start: start.addingTimeInterval(-3600), end: start.addingTimeInterval(7200), calendar: calendar)

        let beforeHide = try await service.agenda(for: window, filter: .agenda)
        #expect(beforeHide.events.contains(where: { $0.externalIdentifier == created.externalIdentifier }))

        service.setCalendarVisible(false, calendarIdentifier: testCalendar.calendarIdentifier)

        let afterHide = try await service.agenda(for: window, filter: .agenda)
        #expect(!afterHide.events.contains(where: { $0.externalIdentifier == created.externalIdentifier }))

        // Un-hiding restores it - the event itself was never touched.
        service.setCalendarVisible(true, calendarIdentifier: testCalendar.calendarIdentifier)
        let afterShow = try await service.agenda(for: window, filter: .agenda)
        #expect(afterShow.events.contains(where: { $0.externalIdentifier == created.externalIdentifier }))

        try await service.deleteEvent(created, span: .thisEvent)
    }
}

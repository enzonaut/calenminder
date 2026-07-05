import Foundation
import EventKit
@testable import CalenminderKit

/// The "seeded fixture-store abstraction" DW-3.1 asks for: an in-memory
/// implementation of `EventProviding`/`ReminderProviding` with zero EventKit
/// runtime dependency in its data (only the plain enums `EKAuthorizationStatus`/
/// `EKEntityType`/`EKSpan` appear, all constructible without a store). Tests
/// seed `events`/`reminders` directly, configure `eventAuthStatus`/
/// `reminderAuthStatus` to exercise every permission branch, and read back
/// `refreshCallCount`/`createdCalendars` to assert on call shape.
///
/// Recurring series are modeled as multiple `RawEventRecord`s sharing one
/// `externalIdentifier` with different `occurrenceDate`s, mirroring how
/// EventKit hands back pre-expanded occurrences -- this is what lets
/// `.thisEvent` vs `.futureEvents` span semantics be exercised here without
/// the real system store (see `EventKitEventStoreTests` span tests; the real
/// store's guarantee that this doesn't corrupt a detached occurrence is
/// DW-3.2's job, verified only by the simulator-only integration test).
final class FixtureCalendarProvider {
    var events: [RawEventRecord] = []
    var reminders: [(record: RawReminderRecord, calendarIdentifier: String)] = []
    private var calendarNames: [String: String] = [:]   // calendarIdentifier -> name
    private(set) var createdCalendars: [String] = []
    private(set) var refreshCallCount = 0

    var eventAuthStatus: EKAuthorizationStatus = .fullAccess
    var reminderAuthStatus: EKAuthorizationStatus = .fullAccess
    /// What `requestFullAccessTo*()` resolves to when authorization is
    /// `.notDetermined`.
    var requestAccessGranted = true
    /// If set, the next mutating call (create/update/delete/complete/
    /// reschedule) throws this wrapped in `ProviderError.underlying`, then
    /// clears itself.
    var forcedSaveError: Error?

    private var changeContinuation: AsyncStream<Void>.Continuation?
    lazy var changes: AsyncStream<Void> = AsyncStream { continuation in
        self.changeContinuation = continuation
    }

    func simulateChange() {
        changeContinuation?.yield(())
    }

    private func consumeForcedError() throws {
        if let error = forcedSaveError {
            forcedSaveError = nil
            throw ProviderError.underlying(error)
        }
    }
}

// MARK: - EventProviding

extension FixtureCalendarProvider: EventProviding {
    func requestFullAccessToEvents() async throws -> Bool { requestAccessGranted }
    func eventAuthorizationStatus() -> EKAuthorizationStatus { eventAuthStatus }

    func fetchEvents(start: Date, end: Date) -> [RawEventRecord] {
        events.filter { $0.start < end && $0.end > start }
    }

    func createEvent(_ draft: RawEventDraft) throws -> RawEventRecord {
        try consumeForcedError()
        let record = RawEventRecord(
            externalIdentifier: UUID().uuidString,
            occurrenceDate: draft.start,
            title: draft.title,
            start: draft.start,
            end: draft.end,
            isAllDay: draft.isAllDay,
            attendeeStatus: nil,
            isOrganizer: true,
            calendarIdentifier: draft.calendarIdentifier ?? "default-calendar"
        )
        events.append(record)
        return record
    }

    func updateEvent(externalIdentifier: String, occurrenceDate: Date, draft: RawEventDraft, span: EKSpan) throws -> RawEventRecord {
        try consumeForcedError()
        guard let anchorIndex = events.firstIndex(where: {
            $0.externalIdentifier == externalIdentifier && $0.occurrenceDate == occurrenceDate
        }) else {
            throw ProviderError.itemNotFound
        }

        let indices: [Int]
        switch span {
        case .thisEvent:
            indices = [anchorIndex]
        case .futureEvents:
            indices = events.indices.filter {
                events[$0].externalIdentifier == externalIdentifier && events[$0].occurrenceDate >= occurrenceDate
            }
        @unknown default:
            indices = [anchorIndex]
        }

        for index in indices {
            events[index].title = draft.title
            events[index].start = draft.start
            events[index].end = draft.end
            events[index].isAllDay = draft.isAllDay
            if let calendarIdentifier = draft.calendarIdentifier {
                events[index].calendarIdentifier = calendarIdentifier
            }
        }
        return events[anchorIndex]
    }

    func deleteEvent(externalIdentifier: String, occurrenceDate: Date, span: EKSpan) throws {
        try consumeForcedError()
        guard events.contains(where: { $0.externalIdentifier == externalIdentifier && $0.occurrenceDate == occurrenceDate }) else {
            throw ProviderError.itemNotFound
        }
        switch span {
        case .thisEvent:
            events.removeAll { $0.externalIdentifier == externalIdentifier && $0.occurrenceDate == occurrenceDate }
        case .futureEvents:
            events.removeAll { $0.externalIdentifier == externalIdentifier && $0.occurrenceDate >= occurrenceDate }
        @unknown default:
            events.removeAll { $0.externalIdentifier == externalIdentifier && $0.occurrenceDate == occurrenceDate }
        }
    }

    func refreshSourcesIfNecessary() {
        refreshCallCount += 1
    }
}

// MARK: - ReminderProviding

extension FixtureCalendarProvider: ReminderProviding {
    func requestFullAccessToReminders() async throws -> Bool { requestAccessGranted }
    func reminderAuthorizationStatus() -> EKAuthorizationStatus { reminderAuthStatus }

    func taskListCalendar(named name: String) throws -> String {
        if let existing = calendarNames.first(where: { $0.value == name })?.key {
            return existing
        }
        let id = "cal-\(name)-\(UUID().uuidString)"
        calendarNames[id] = name
        createdCalendars.append(name)
        return id
    }

    func fetchReminders(calendarIdentifier: String) async -> [RawReminderRecord] {
        reminders.filter { $0.calendarIdentifier == calendarIdentifier }.map(\.record)
    }

    func fetchIncompleteReminders(calendarIdentifier: String, dueOnOrBefore day: DateComponents) async -> [RawReminderRecord] {
        // Mimics the REAL provider faithfully, boundary quirk included:
        // `SystemCalendarProvider` passes `ending = start of the day AFTER
        // `day`` to `predicateForIncompleteReminders(withDueDateStarting:
        // ending:)`, and EventKit treats a date-only reminder due exactly at
        // that boundary instant (i.e. due *tomorrow*) as matching - confirmed
        // empirically end-to-end (a Monday-due task leaked into Sunday's
        // overdue fetch). This fixture used to filter with an honest civil
        // `due <= day` comparison, which made it *stricter* than the real
        // dependency and hid that leak from every unit test; it now
        // reproduces the instant-based inclusive-boundary behavior so
        // `ReminderTaskStore`'s own civil-day barricade is genuinely
        // exercised.
        let gregorian = Calendar(identifier: .gregorian)
        guard let dayStart = gregorian.date(from: day),
              let ending = gregorian.date(byAdding: .day, value: 1, to: dayStart)
        else { return [] }
        return reminders
            .filter { $0.calendarIdentifier == calendarIdentifier }
            .map(\.record)
            .filter { !$0.isCompleted }
            .filter { record in
                guard let due = gregorian.date(from: record.dueDay) else { return false }
                return due <= ending
            }
    }

    func createReminder(_ draft: RawReminderDraft, calendarIdentifier: String) throws -> RawReminderRecord {
        try consumeForcedError()
        let record = RawReminderRecord(
            externalIdentifier: UUID().uuidString,
            title: draft.title,
            dueDay: draft.dueDay,
            isCompleted: false,
            recurrenceWeekday: draft.recurrenceWeekday,
            recurrenceIsDaily: draft.recurrenceIsDaily
        )
        reminders.append((record, calendarIdentifier))
        return record
    }

    func setReminderCompleted(externalIdentifier: String, completed: Bool) throws -> RawReminderRecord {
        try consumeForcedError()
        guard let index = reminders.firstIndex(where: { $0.record.externalIdentifier == externalIdentifier }) else {
            throw ProviderError.itemNotFound
        }
        reminders[index].record.isCompleted = completed
        return reminders[index].record
    }
}

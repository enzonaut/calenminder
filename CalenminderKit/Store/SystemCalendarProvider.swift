import Foundation
import EventKit

/// The real implementation of `EventProviding`/`ReminderProviding`, backed by
/// one `EKEventStore`. All EventKit-specific translation lives here and only
/// here: predicate construction, completion-handler-to-async wrapping,
/// occurrence re-resolution by `(externalIdentifier, occurrenceDate)`,
/// `EKRecurrenceRule` construction, and `EK*` <-> `Raw*Record` mapping.
///
/// A given instance is used by exactly one of `EventKitEventStore` /
/// `ReminderTaskStore` (each constructs its own), even though this one class
/// implements both protocols -- see the Phase 3 design doc for why the
/// `changes` stream requires that.
final class SystemCalendarProvider {
    private let store: EKEventStore
    let changes: AsyncStream<Void>

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
        self.changes = AsyncStream { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: nil
            ) { _ in continuation.yield(()) }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    // MARK: - Reminder fetch (async, completion-handler wrapped per code-standards)

    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    // MARK: - Event translation

    private static func rawRecord(from event: EKEvent) -> RawEventRecord? {
        guard let identifier = event.calendarItemExternalIdentifier,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let isOrganizer = event.organizer?.isCurrentUser ?? false
        let selfAttendee = event.attendees?.first(where: { $0.isCurrentUser })
        return RawEventRecord(
            externalIdentifier: identifier,
            occurrenceDate: event.startDate,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            attendeeStatus: selfAttendee?.participantStatus,
            isOrganizer: isOrganizer,
            calendarIdentifier: event.calendar?.calendarIdentifier ?? ""
        )
    }

    /// Re-resolves the live `EKEvent` for one occurrence. There is no
    /// identifier-based single-occurrence fetch in EventKit, so this queries
    /// a generous window around `occurrenceDate` and matches by external
    /// identifier + exact start-time equality. Callers that shift an
    /// occurrence's time must pass the *original* `occurrenceDate` (see the
    /// Phase 3 design doc's occurrence-identity contract).
    private func resolveEvent(externalIdentifier: String, occurrenceDate: Date) -> EKEvent? {
        let searchStart = occurrenceDate.addingTimeInterval(-2 * 86_400)
        let searchEnd = occurrenceDate.addingTimeInterval(2 * 86_400)
        let predicate = store.predicateForEvents(withStart: searchStart, end: searchEnd, calendars: nil)
        return store.events(matching: predicate).first {
            $0.calendarItemExternalIdentifier == externalIdentifier
                && abs($0.startDate.timeIntervalSince(occurrenceDate)) < 1
        }
    }

    private func apply(_ draft: RawEventDraft, to event: EKEvent) {
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        if let calendarIdentifier = draft.calendarIdentifier, let calendar = store.calendar(withIdentifier: calendarIdentifier) {
            event.calendar = calendar
        } else if event.calendar == nil {
            event.calendar = store.defaultCalendarForNewEvents
        }
    }

    // MARK: - Reminder translation

    private static func rawRecord(from reminder: EKReminder) -> RawReminderRecord? {
        guard let identifier = reminder.calendarItemExternalIdentifier,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return RawReminderRecord(
            externalIdentifier: identifier,
            title: reminder.title ?? "",
            dueDay: reminder.dueDateComponents ?? DateComponents(),
            isCompleted: reminder.isCompleted,
            recurrenceWeekday: EventKitRecurrence.weeklyWeekday(from: reminder.recurrenceRules),
            recurrenceIsDaily: EventKitRecurrence.isDaily(from: reminder.recurrenceRules)
        )
    }

    private func resolveReminder(externalIdentifier: String) -> EKReminder? {
        store.calendarItems(withExternalIdentifier: externalIdentifier).first as? EKReminder
    }

    private static func gregorianComponents(_ components: DateComponents) -> DateComponents {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.year = components.year
        c.month = components.month
        c.day = components.day
        return c
    }
}

// MARK: - EventProviding

extension SystemCalendarProvider: EventProviding {
    func requestFullAccessToEvents() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func eventAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func fetchEvents(start: Date, end: Date) -> [RawEventRecord] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap(Self.rawRecord(from:))
    }

    func createEvent(_ draft: RawEventDraft) throws -> RawEventRecord {
        let event = EKEvent(eventStore: store)
        apply(draft, to: event)
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw ProviderError.underlying(error)
        }
        guard let record = Self.rawRecord(from: event) else { throw ProviderError.itemNotFound }
        return record
    }

    func updateEvent(externalIdentifier: String, occurrenceDate: Date, draft: RawEventDraft, span: EKSpan) throws -> RawEventRecord {
        guard let event = resolveEvent(externalIdentifier: externalIdentifier, occurrenceDate: occurrenceDate) else {
            throw ProviderError.itemNotFound
        }
        apply(draft, to: event)
        do {
            try store.save(event, span: span, commit: true)
        } catch {
            throw ProviderError.underlying(error)
        }
        guard let record = Self.rawRecord(from: event) else { throw ProviderError.itemNotFound }
        return record
    }

    func deleteEvent(externalIdentifier: String, occurrenceDate: Date, span: EKSpan) throws {
        guard let event = resolveEvent(externalIdentifier: externalIdentifier, occurrenceDate: occurrenceDate) else {
            throw ProviderError.itemNotFound
        }
        do {
            try store.remove(event, span: span, commit: true)
        } catch {
            throw ProviderError.underlying(error)
        }
    }

    func refreshSourcesIfNecessary() {
        store.refreshSourcesIfNecessary()
    }
}

// MARK: - ReminderProviding

extension SystemCalendarProvider: ReminderProviding {
    func requestFullAccessToReminders() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    func reminderAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    func taskListCalendar(named name: String) throws -> String {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == name }) {
            return existing.calendarIdentifier
        }
        guard let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        else {
            throw ProviderError.underlying(CalendarStoreError.saveFailed(underlying: CocoaError(.featureUnsupported)))
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            throw ProviderError.underlying(error)
        }
        return calendar.calendarIdentifier
    }

    func fetchReminders(calendarIdentifier: String) async -> [RawReminderRecord] {
        guard let calendar = store.calendar(withIdentifier: calendarIdentifier) else { return [] }
        let predicate = store.predicateForReminders(in: [calendar])
        let reminders = await fetchReminders(matching: predicate)
        return reminders.compactMap(Self.rawRecord(from:))
    }

    func fetchIncompleteReminders(calendarIdentifier: String, dueOnOrBefore day: DateComponents) async -> [RawReminderRecord] {
        guard let calendar = store.calendar(withIdentifier: calendarIdentifier) else { return [] }
        let gregorian = Calendar(identifier: .gregorian)
        guard let dayStart = gregorian.date(from: day),
              let ending = gregorian.date(byAdding: .day, value: 1, to: dayStart)
        else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: ending, calendars: [calendar])
        let reminders = await fetchReminders(matching: predicate)
        return reminders.compactMap(Self.rawRecord(from:))
    }

    func createReminder(_ draft: RawReminderDraft, calendarIdentifier: String) throws -> RawReminderRecord {
        guard let calendar = store.calendar(withIdentifier: calendarIdentifier) else {
            throw ProviderError.itemNotFound
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.calendar = calendar
        reminder.dueDateComponents = Self.gregorianComponents(draft.dueDay)
        if let weekday = draft.recurrenceWeekday, let rule = EventKitRecurrence.weeklyRule(weekday: weekday) {
            reminder.addRecurrenceRule(rule)
        } else if draft.recurrenceIsDaily {
            reminder.addRecurrenceRule(EventKitRecurrence.dailyRule())
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw ProviderError.underlying(error)
        }
        guard let record = Self.rawRecord(from: reminder) else { throw ProviderError.itemNotFound }
        return record
    }

    func setReminderCompleted(externalIdentifier: String, completed: Bool) throws -> RawReminderRecord {
        guard let reminder = resolveReminder(externalIdentifier: externalIdentifier) else {
            throw ProviderError.itemNotFound
        }
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw ProviderError.underlying(error)
        }
        guard let record = Self.rawRecord(from: reminder) else { throw ProviderError.itemNotFound }
        return record
    }

}

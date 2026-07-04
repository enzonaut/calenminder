import Foundation
@testable import CalenminderKit

/// Fake `EventStoring`. One layer up from Phase 3's `FixtureCalendarProvider`
/// (which fakes `EventProviding` beneath `EventKitEventStore`) - this fakes
/// the pinned Domain seam directly, which is what `AgendaService` consumes,
/// so its tests never touch EventKit at all.
final class FakeEventStore: EventStoring {
    var events: [Event] = []
    var fetchError: Error?
    var createResult: Result<Event, Error>?
    var updateError: Error?
    var deleteError: Error?
    private(set) var createdDrafts: [EventDraft] = []
    private(set) var updatedEvents: [(Event, EditSpan)] = []
    private(set) var deletedEvents: [(Event, EditSpan)] = []

    private let continuation: AsyncStream<Void>.Continuation
    let changes: AsyncStream<Void>

    init() {
        var continuation: AsyncStream<Void>.Continuation!
        self.changes = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func fireChange() { continuation.yield(()) }

    func events(in window: DayWindow) async throws -> [Event] {
        if let fetchError { throw fetchError }
        return events.filter { window.contains($0) }
    }

    func create(_ draft: EventDraft) async throws -> Event {
        createdDrafts.append(draft)
        let created: Event
        switch createResult {
        case .success(let event): created = event
        case .failure(let error): throw error
        case nil: created = Event(externalIdentifier: "new", occurrenceDate: draft.start, title: draft.title, start: draft.start, end: draft.end, isAllDay: draft.isAllDay, participation: .notInvited, calendarIdentifier: draft.calendarIdentifier ?? "default")
        }
        events.append(created)
        return created
    }

    func update(_ event: Event, span: EditSpan) async throws {
        updatedEvents.append((event, span))
        if let updateError { throw updateError }
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        }
    }

    func delete(_ event: Event, span: EditSpan) async throws {
        deletedEvents.append((event, span))
        if let deleteError { throw deleteError }
        events.removeAll { $0.id == event.id }
    }
}

/// Fake `TaskStoring` - see `FakeEventStore`'s doc.
final class FakeTaskStore: TaskStoring {
    var tasks: [DayTask] = []
    var addResult: Result<DayTask, Error>?
    var setCompletedError: Error?
    /// Thrown by both fetch methods below, mirroring `FakeEventStore.fetchError`
    /// - lets tests simulate a Reminders-access-denied (or any other) fetch
    /// failure, which `FakeTaskStore` had no way to model before Phase 5
    /// needed to exercise `WidgetContentLoader`'s `.remindersAccessDenied`
    /// mapping path.
    var fetchError: Error?
    private(set) var addedDrafts: [TaskDraft] = []
    private(set) var completionCalls: [(DayTask, Bool)] = []

    private let continuation: AsyncStream<Void>.Continuation
    let changes: AsyncStream<Void>

    init() {
        var continuation: AsyncStream<Void>.Continuation!
        self.changes = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func fireChange() { continuation.yield(()) }

    /// Counts real fetches - lets a test prove `AgendaViewModel.load()`'s
    /// reload-coalescing guard collapses N overlapping requests into far
    /// fewer than N real fetches (the checkmark-completion race regression;
    /// see `AgendaViewModelTests.concurrentLoadsCoalesceRatherThanRaceEachOthersFetch`).
    private(set) var tasksDueOnCallCount = 0

    func tasks(dueOn day: DayStamp, includeCompleted: Bool) async throws -> [DayTask] {
        tasksDueOnCallCount += 1
        if let fetchError { throw fetchError }
        return tasks.filter { $0.dueDay == day && (includeCompleted || !$0.isCompleted) }
    }

    func incompleteTasks(overdueAsOf day: DayStamp) async throws -> [DayTask] {
        if let fetchError { throw fetchError }
        return tasks.filter { $0.dueDay <= day && !$0.isCompleted }
    }

    private(set) var incompleteTasksDueBetweenCallCount = 0

    func incompleteTasks(dueBetween start: DayStamp, and end: DayStamp) async throws -> [DayTask] {
        incompleteTasksDueBetweenCallCount += 1
        if let fetchError { throw fetchError }
        return tasks.filter { $0.dueDay >= start && $0.dueDay <= end && !$0.isCompleted }
    }

    func add(_ draft: TaskDraft) async throws -> DayTask {
        addedDrafts.append(draft)
        let created: DayTask
        switch addResult {
        case .success(let task): created = task
        case .failure(let error): throw error
        case nil: created = DayTask(externalIdentifier: "new-task", title: draft.title, dueDay: draft.dueDay, isCompleted: false, recurrence: draft.recurrence)
        }
        tasks.append(created)
        return created
    }

    func setCompleted(_ task: DayTask, _ completed: Bool) async throws {
        completionCalls.append((task, completed))
        if let setCompletedError { throw setCompletedError }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = DayTask(
                externalIdentifier: task.externalIdentifier, title: task.title,
                dueDay: task.dueDay, isCompleted: completed, recurrence: task.recurrence
            )
        }
    }
}

final class FakeCalendarDirectory: EventCalendarDirectory {
    var result: Result<[EventCalendarInfo], Error> = .success([])

    func calendars() async throws -> [EventCalendarInfo] {
        try result.get()
    }
}

final class FakeCalendarVisibilityStore: CalendarVisibilityStoring {
    private var hidden: Set<String> = []

    func isVisible(calendarIdentifier: String) -> Bool { !hidden.contains(calendarIdentifier) }

    func setVisible(_ visible: Bool, calendarIdentifier: String) {
        if visible { hidden.remove(calendarIdentifier) } else { hidden.insert(calendarIdentifier) }
    }
}

final class FakeWidgetReloader: WidgetReloading {
    private(set) var reloadCount = 0
    func reloadAllTimelines() { reloadCount += 1 }
}

enum TestError: Error, Equatable { case boom }

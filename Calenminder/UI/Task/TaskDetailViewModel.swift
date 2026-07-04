import Foundation
import CalenminderKit

/// Resolves and displays one task by identifier - reached from a `task` deep
/// link. Best-effort by nature (see `AgendaService.resolveTask`'s doc); a
/// miss renders `.notFound`, never a crash (DW-4.4).
@MainActor
final class TaskDetailViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case found(DayTask)
        case notFound
        case error(String)
    }

    @Published private(set) var state: State = .loading

    let externalIdentifier: String
    private let agenda: AgendaViewModel

    init(agenda: AgendaViewModel, externalIdentifier: String) {
        self.agenda = agenda
        self.externalIdentifier = externalIdentifier
    }

    /// Human-readable recurrence line for the found task, `nil` when there is
    /// no task yet or it does not recur.
    var recurrenceDescription: String? {
        guard case .found(let task) = state, let recurrence = task.recurrence else { return nil }
        return Self.describe(recurrence)
    }

    private static func describe(_ recurrence: TaskRecurrence) -> String {
        switch recurrence {
        case .daily:
            return "Repeats daily"
        case .weekly(let weekday):
            // Defensive: a garbled weekday degrades to generic copy rather
            // than crashing on an out-of-range `weekdaySymbols` index,
            // matching this codebase's "garbled input excluded gracefully"
            // pattern.
            guard (1...7).contains(weekday) else { return "Repeats weekly" }
            return "Repeats every \(Calendar.current.weekdaySymbols[weekday - 1])"
        }
    }

    func load() async {
        state = .loading
        do {
            guard let task = try await agenda.resolveTask(externalIdentifier: externalIdentifier) else {
                state = .notFound
                return
            }
            state = .found(task)
        } catch {
            state = .error(ErrorPresentation.message(for: error))
        }
    }

    func toggleCompletion() async {
        guard case .found(let task) = state else { return }
        await agenda.toggleTaskCompletion(task)
        await load()
    }
}

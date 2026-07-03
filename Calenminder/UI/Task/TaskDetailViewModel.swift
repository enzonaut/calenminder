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

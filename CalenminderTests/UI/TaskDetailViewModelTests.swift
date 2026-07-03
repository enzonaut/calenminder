import Testing
import Foundation
@testable import Calenminder
@testable import CalenminderKit

@MainActor
struct TaskDetailViewModelTests {
    private func makeAgenda(tasks: FakeTaskStore = FakeTaskStore(), day: DayStamp) -> AgendaViewModel {
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: tasks)
        return AgendaViewModel(agendaService: service, day: day, calendar: .current)
    }

    @Test("DW-4.3: load() finds an existing task due today")
    func loadFindsTaskDueToday() async {
        let day = DayStamp(date: Date(), calendar: .current)
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "t1", title: "Water plants", due: day)]
        let agenda = makeAgenda(tasks: tasks, day: day)
        let viewModel = TaskDetailViewModel(agenda: agenda, externalIdentifier: "t1")

        await viewModel.load()

        guard case .found(let task) = viewModel.state else {
            Issue.record("expected .found, got \(viewModel.state)")
            return
        }
        #expect(task.title == "Water plants")
    }

    @Test("DW-4.4: load() with an unknown task ID resolves to .notFound, never crashes")
    func test_DW_4_4_unknownTaskIDResolvesToNotFound() async {
        let day = DayStamp(date: Date(), calendar: .current)
        let agenda = makeAgenda(day: day)
        let viewModel = TaskDetailViewModel(agenda: agenda, externalIdentifier: "does-not-exist")

        await viewModel.load()

        #expect(viewModel.state == .notFound)
    }

    @Test("toggleCompletion() flips an incomplete task to completed")
    func toggleCompletionMarksComplete() async {
        let day = DayStamp(date: Date(), calendar: .current)
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "t1", due: day, completed: false)]
        let agenda = makeAgenda(tasks: tasks, day: day)
        let viewModel = TaskDetailViewModel(agenda: agenda, externalIdentifier: "t1")
        await viewModel.load()

        await viewModel.toggleCompletion()

        #expect(tasks.completionCalls.last?.1 == true)
    }
}

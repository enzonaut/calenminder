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

    @Test("DW-F1.3: recurrenceDescription is nil for a non-recurring task")
    func test_DW_F1_3_recurrenceDescriptionNilForNonRecurringTask() async {
        let day = DayStamp(date: Date(), calendar: .current)
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "t1", due: day)]
        let agenda = makeAgenda(tasks: tasks, day: day)
        let viewModel = TaskDetailViewModel(agenda: agenda, externalIdentifier: "t1")

        await viewModel.load()

        #expect(viewModel.recurrenceDescription == nil)
    }

    @Test("DW-F1.3: recurrenceDescription reads 'Repeats daily' for a daily task")
    func test_DW_F1_3_recurrenceDescriptionForDailyTask() async {
        let day = DayStamp(date: Date(), calendar: .current)
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "t1", due: day, recurrence: .daily)]
        let agenda = makeAgenda(tasks: tasks, day: day)
        let viewModel = TaskDetailViewModel(agenda: agenda, externalIdentifier: "t1")

        await viewModel.load()

        #expect(viewModel.recurrenceDescription == "Repeats daily")
    }

    @Test("recurrenceDescription names the weekday for a weekly task")
    func recurrenceDescriptionForWeeklyTask() async {
        let day = DayStamp(date: Date(), calendar: .current)
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "t1", due: day, recurrence: .weekly(weekday: 2))]
        let agenda = makeAgenda(tasks: tasks, day: day)
        let viewModel = TaskDetailViewModel(agenda: agenda, externalIdentifier: "t1")

        await viewModel.load()

        #expect(viewModel.recurrenceDescription == "Repeats every \(Calendar.current.weekdaySymbols[1])")
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

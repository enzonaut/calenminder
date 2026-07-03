import Testing
import Foundation
@testable import Calenminder
@testable import CalenminderKit

@MainActor
struct TaskComposerViewModelTests {
    private func makeAgenda(tasks: FakeTaskStore = FakeTaskStore(), day: DayStamp) -> AgendaViewModel {
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: tasks)
        return AgendaViewModel(agendaService: service, day: day, calendar: .current)
    }

    @Test("DW-4.3: canSave is false for a blank title")
    func canSaveFalseForBlankTitle() {
        let day = DayStamp(year: 2026, month: 7, day: 3)
        let viewModel = TaskComposerViewModel(agenda: makeAgenda(day: day), dueDay: day)
        viewModel.title = "   "
        #expect(viewModel.canSave == false)
    }

    @Test("weekday defaults to the due day's own weekday")
    func weekdayDefaultsToDueDayWeekday() {
        // 2026-07-03 is a Friday -> Gregorian weekday 6.
        let day = DayStamp(year: 2026, month: 7, day: 3)
        let viewModel = TaskComposerViewModel(agenda: makeAgenda(day: day), dueDay: day)
        #expect(viewModel.weekday == 6)
    }

    @Test("DW-4.2: saving creates a non-recurring task by default")
    func savingCreatesNonRecurringTask() async {
        let day = DayStamp(year: 2026, month: 7, day: 3)
        let tasks = FakeTaskStore()
        let viewModel = TaskComposerViewModel(agenda: makeAgenda(tasks: tasks, day: day), dueDay: day)
        viewModel.title = "Take out trash"

        let created = await viewModel.save()

        #expect(created?.title == "Take out trash")
        #expect(tasks.addedDrafts.last?.recurrence == nil)
    }

    @Test("DW-4.2: saving with repeatsWeekly creates a weekly-recurring task")
    func savingWithRepeatsWeeklyCreatesRecurringTask() async {
        let day = DayStamp(year: 2026, month: 7, day: 3)
        let tasks = FakeTaskStore()
        let viewModel = TaskComposerViewModel(agenda: makeAgenda(tasks: tasks, day: day), dueDay: day)
        viewModel.title = "Water plants"
        viewModel.repeatsWeekly = true
        viewModel.weekday = 2

        _ = await viewModel.save()

        #expect(tasks.addedDrafts.last?.recurrence == .weekly(weekday: 2))
    }

    @Test("A failed save surfaces an error and returns nil")
    func failedSaveSurfacesError() async {
        let day = DayStamp(year: 2026, month: 7, day: 3)
        let tasks = FakeTaskStore()
        tasks.addResult = .failure(TestError.boom)
        let viewModel = TaskComposerViewModel(agenda: makeAgenda(tasks: tasks, day: day), dueDay: day)
        viewModel.title = "Water plants"

        let created = await viewModel.save()

        #expect(created == nil)
        #expect(viewModel.errorMessage != nil)
    }
}

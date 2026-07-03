import Testing
import Foundation
@testable import Calenminder
@testable import CalenminderKit

@MainActor
struct EventEditViewModelTests {
    private func makeAgenda(events: FakeEventStore = FakeEventStore()) -> AgendaViewModel {
        let service = AgendaService(eventStore: events, taskStore: FakeTaskStore())
        return AgendaViewModel(agendaService: service, calendar: .current)
    }

    @Test("DW-4.3: canSave is false for a blank title")
    func canSaveFalseForBlankTitle() {
        let viewModel = EventEditViewModel(agenda: makeAgenda(), mode: .create)
        viewModel.title = "   "
        #expect(viewModel.canSave == false)
    }

    @Test("canSave is false when end precedes start")
    func canSaveFalseWhenEndBeforeStart() {
        let viewModel = EventEditViewModel(agenda: makeAgenda(), mode: .create)
        viewModel.title = "Meeting"
        viewModel.start = Date()
        viewModel.end = viewModel.start.addingTimeInterval(-3600)
        #expect(viewModel.canSave == false)
    }

    @Test("DW-4.2/DW-4.3: creating a new event calls through to the agenda service")
    func createCallsAgendaService() async {
        let events = FakeEventStore()
        let agenda = makeAgenda(events: events)
        let viewModel = EventEditViewModel(agenda: agenda, mode: .create)
        viewModel.title = "Standup"

        let succeeded = await viewModel.save()

        #expect(succeeded == true)
        #expect(events.createdDrafts.map(\.title) == ["Standup"])
    }

    @Test("DW-4.2: editing an event forwards the chosen span")
    func editForwardsSpan() async {
        let events = FakeEventStore()
        let original = Fixture.event(id: "e1", title: "Standup", start: Date(), end: Date().addingTimeInterval(1800))
        events.events = [original]
        let agenda = makeAgenda(events: events)
        let viewModel = EventEditViewModel(agenda: agenda, mode: .edit(original: original))
        viewModel.title = "Standup (renamed)"
        viewModel.span = .futureEvents

        let succeeded = await viewModel.save()

        #expect(succeeded == true)
        #expect(events.updatedEvents.last?.0.title == "Standup (renamed)")
        #expect(events.updatedEvents.last?.1 == .futureEvents)
    }

    @Test("DW-4.4/Edge case: a failed save surfaces an error and does not clear the form")
    func failedSaveSurfacesErrorWithoutClearingForm() async {
        let events = FakeEventStore()
        events.createResult = .failure(TestError.boom)
        let viewModel = EventEditViewModel(agenda: makeAgenda(events: events), mode: .create)
        viewModel.title = "Standup"

        let succeeded = await viewModel.save()

        #expect(succeeded == false)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.title == "Standup")
    }

    @Test("isEditing reflects the mode")
    func isEditingReflectsMode() {
        let createVM = EventEditViewModel(agenda: makeAgenda(), mode: .create)
        #expect(createVM.isEditing == false)

        let event = Fixture.event(id: "e1", start: Date(), end: Date().addingTimeInterval(1800))
        let editVM = EventEditViewModel(agenda: makeAgenda(), mode: .edit(original: event))
        #expect(editVM.isEditing == true)
    }
}

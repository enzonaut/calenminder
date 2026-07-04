import Testing
import Foundation
@testable import Calenminder
@testable import CalenminderKit

@MainActor
struct EventDetailViewModelTests {
    private func makeAgenda(events: FakeEventStore = FakeEventStore()) -> AgendaViewModel {
        let service = AgendaService(eventStore: events, taskStore: FakeTaskStore())
        return AgendaViewModel(agendaService: service, calendar: .current)
    }

    @Test("DW-4.3: load() finds an existing event, including a declined one (invite-detail visibility)")
    func loadFindsDeclinedEvent() async {
        let occurrence = Date()
        let events = FakeEventStore()
        events.events = [Fixture.event(id: "e1", start: occurrence, end: occurrence.addingTimeInterval(3600), status: .declined, occurrence: occurrence)]
        let agenda = makeAgenda(events: events)
        let viewModel = EventDetailViewModel(agenda: agenda, externalIdentifier: "e1", occurrenceDate: occurrence)

        await viewModel.load()

        guard case .found(let event) = viewModel.state else {
            Issue.record("expected .found, got \(viewModel.state)")
            return
        }
        #expect(event.participation == .declined)
    }

    @Test("DW-4.4: load() with an unknown event ID resolves to .notFound, never crashes")
    func test_DW_4_4_unknownEventIDResolvesToNotFound() async {
        let agenda = makeAgenda()
        let viewModel = EventDetailViewModel(agenda: agenda, externalIdentifier: "does-not-exist", occurrenceDate: Date())

        await viewModel.load()

        #expect(viewModel.state == .notFound)
    }

    @Test("delete() removes the event and transitions to .notFound on success")
    func deleteTransitionsToNotFoundOnSuccess() async {
        let occurrence = Date()
        let events = FakeEventStore()
        events.events = [Fixture.event(id: "e1", start: occurrence, end: occurrence.addingTimeInterval(3600), occurrence: occurrence)]
        let agenda = makeAgenda(events: events)
        let viewModel = EventDetailViewModel(agenda: agenda, externalIdentifier: "e1", occurrenceDate: occurrence)
        await viewModel.load()

        let deleted = await viewModel.delete(span: .thisEvent)

        #expect(deleted == true)
        #expect(viewModel.state == .notFound)
    }

    @Test("delete() surfaces an error and stays on the found event when the store fails")
    func deleteSurfacesErrorOnFailure() async {
        let occurrence = Date()
        let events = FakeEventStore()
        events.events = [Fixture.event(id: "e1", start: occurrence, end: occurrence.addingTimeInterval(3600), occurrence: occurrence)]
        events.deleteError = TestError.boom
        let agenda = makeAgenda(events: events)
        let viewModel = EventDetailViewModel(agenda: agenda, externalIdentifier: "e1", occurrenceDate: occurrence)
        await viewModel.load()

        let deleted = await viewModel.delete(span: .thisEvent)

        #expect(deleted == false)
        guard case .found = viewModel.state else {
            Issue.record("expected to remain .found after a failed delete")
            return
        }
        #expect(agenda.errorMessage != nil)
    }
}

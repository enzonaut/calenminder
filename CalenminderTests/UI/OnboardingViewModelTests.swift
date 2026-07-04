import Testing
import Foundation
@testable import Calenminder
@testable import CalenminderKit

@MainActor
struct OnboardingViewModelTests {
    @Test("DW-4.3: start() transitions to .granted when the agenda service can read")
    func startTransitionsToGrantedOnSuccess() async {
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: FakeTaskStore())
        let viewModel = OnboardingViewModel(agendaService: service, calendar: .current)

        await viewModel.start()

        #expect(viewModel.state == .granted)
    }

    @Test("DW-4.3: start() transitions to .needsPermission with a message when access is denied")
    func startTransitionsToNeedsPermissionOnFailure() async {
        let events = FakeEventStore()
        events.fetchError = CalendarStoreError.accessDenied(.event)
        let service = AgendaService(eventStore: events, taskStore: FakeTaskStore())
        let viewModel = OnboardingViewModel(agendaService: service, calendar: .current)

        await viewModel.start()

        guard case .needsPermission(let message) = viewModel.state else {
            Issue.record("expected .needsPermission, got \(viewModel.state)")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("start() surfaces a non-store error message too")
    func startSurfacesGenericErrorMessage() async {
        let events = FakeEventStore()
        events.fetchError = TestError.boom
        let service = AgendaService(eventStore: events, taskStore: FakeTaskStore())
        let viewModel = OnboardingViewModel(agendaService: service, calendar: .current)

        await viewModel.start()

        guard case .needsPermission = viewModel.state else {
            Issue.record("expected .needsPermission, got \(viewModel.state)")
            return
        }
    }
}

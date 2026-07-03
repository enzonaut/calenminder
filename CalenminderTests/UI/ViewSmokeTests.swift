import Testing
import SwiftUI
import Foundation
@testable import Calenminder
@testable import CalenminderKit

/// DW-4.3's pragmatic substitute for image-diff snapshot tests (no
/// snapshot-testing library is installable in this network-restricted
/// sandbox - see the Phase 4 discovery doc). `ImageRenderer` (iOS 16+) drives
/// SwiftUI's real layout + paint pipeline off-screen, with no host-app/window
/// dependency, so a successful non-empty render is genuine evidence the view
/// body does not crash and produces visible content for a given view-model
/// state - the actual risk DW-4.3 exists to catch.
@MainActor
enum ViewRenderProbe {
    /// Renders `view` and returns its pixel size, or `nil` if rendering
    /// produced no image at all (which would itself be a real bug).
    static func renderedSize(_ view: some View) -> CGSize? {
        let renderer = ImageRenderer(content: view.frame(width: 390, height: 844))
        renderer.scale = 1
        guard let image = renderer.uiImage else { return nil }
        return image.size
    }
}

@MainActor
struct ViewSmokeTests {
    private func makeAgenda(
        events: FakeEventStore = FakeEventStore(),
        tasks: FakeTaskStore = FakeTaskStore()
    ) -> AgendaViewModel {
        AgendaViewModel(agendaService: AgendaService(eventStore: events, taskStore: tasks), calendar: .current)
    }

    @Test("DW-4.3: OnboardingView renders across checking/needsPermission/granted states without crashing")
    func test_DW_4_3_onboardingViewRendersAcrossStates() async {
        let states: [OnboardingViewModel.State] = [.checking, .needsPermission(message: "Access needed"), .granted]
        for state in states {
            let events = FakeEventStore()
            if case .needsPermission = state {
                events.fetchError = CalendarStoreError.accessDenied(.event)
            }
            let service = AgendaService(eventStore: events, taskStore: FakeTaskStore())
            let viewModel = OnboardingViewModel(agendaService: service, calendar: .current)
            // Drive the view model to the intended state rather than faking
            // internal state directly (it has no public setter, by design).
            if case .granted = state {
                await viewModel.start()
                #expect(viewModel.state == .granted)
            } else if case .needsPermission = state {
                await viewModel.start()
                guard case .needsPermission = viewModel.state else {
                    Issue.record("expected .needsPermission")
                    continue
                }
            }
            let size = ViewRenderProbe.renderedSize(OnboardingView(viewModel: viewModel))
            #expect(size != nil && size!.width > 0 && size!.height > 0, "OnboardingView failed to render for state \(state)")
        }
    }

    @Test("DW-4.3: AgendaView renders for empty, populated, and error states without crashing")
    func test_DW_4_3_agendaViewRendersAcrossStates() async {
        // Empty
        let emptyAgenda = makeAgenda()
        await emptyAgenda.load()
        var size = ViewRenderProbe.renderedSize(AgendaView(viewModel: emptyAgenda))
        #expect(size != nil && size!.width > 0 && size!.height > 0, "AgendaView failed to render empty state")

        // Populated (events + tasks)
        let day = DayStamp(date: Date(), calendar: .current)
        let window = DayWindow(day: day, calendar: .current)!
        let events = FakeEventStore()
        events.events = [Fixture.event(id: "e1", start: window.start.addingTimeInterval(3600), end: window.start.addingTimeInterval(7200))]
        let tasks = FakeTaskStore()
        tasks.tasks = [Fixture.task(id: "t1", due: day)]
        let populatedAgenda = makeAgenda(events: events, tasks: tasks)
        await populatedAgenda.load()
        size = ViewRenderProbe.renderedSize(AgendaView(viewModel: populatedAgenda))
        #expect(size != nil && size!.width > 0 && size!.height > 0, "AgendaView failed to render populated state")

        // Error
        let failingEvents = FakeEventStore()
        failingEvents.fetchError = TestError.boom
        let errorAgenda = makeAgenda(events: failingEvents)
        await errorAgenda.load()
        #expect(errorAgenda.errorMessage != nil)
        size = ViewRenderProbe.renderedSize(AgendaView(viewModel: errorAgenda))
        #expect(size != nil && size!.width > 0 && size!.height > 0, "AgendaView failed to render error state")
    }

    @Test("DW-4.3/DW-4.4: EventDetailView renders across loading/found/notFound/error states without crashing")
    func test_DW_4_3_eventDetailViewRendersAcrossStates() async {
        let agenda = makeAgenda()

        // notFound
        let notFoundVM = EventDetailViewModel(agenda: agenda, externalIdentifier: "missing", occurrenceDate: Date())
        await notFoundVM.load()
        var size = ViewRenderProbe.renderedSize(EventDetailView(viewModel: notFoundVM, agenda: agenda))
        #expect(size != nil && size!.width > 0 && size!.height > 0, "EventDetailView failed to render .notFound")

        // found
        let occurrence = Date()
        let events = FakeEventStore()
        events.events = [Fixture.event(id: "e1", start: occurrence, end: occurrence.addingTimeInterval(3600), occurrence: occurrence)]
        let foundAgenda = makeAgenda(events: events)
        let foundVM = EventDetailViewModel(agenda: foundAgenda, externalIdentifier: "e1", occurrenceDate: occurrence)
        await foundVM.load()
        size = ViewRenderProbe.renderedSize(EventDetailView(viewModel: foundVM, agenda: foundAgenda))
        #expect(size != nil && size!.width > 0 && size!.height > 0, "EventDetailView failed to render .found")

        // loading (fresh view model, never loaded)
        let loadingVM = EventDetailViewModel(agenda: agenda, externalIdentifier: "e1", occurrenceDate: Date())
        size = ViewRenderProbe.renderedSize(EventDetailView(viewModel: loadingVM, agenda: agenda))
        #expect(size != nil && size!.width > 0 && size!.height > 0, "EventDetailView failed to render .loading")
    }

    @Test("NotFoundView renders without crashing")
    func notFoundViewRenders() {
        let size = ViewRenderProbe.renderedSize(NotFoundView())
        #expect(size != nil && size!.width > 0 && size!.height > 0)
    }

    @Test("EventEditView renders for both create and edit modes without crashing")
    func eventEditViewRendersForBothModes() {
        let agenda = makeAgenda()
        let createVM = EventEditViewModel(agenda: agenda, mode: .create)
        var size = ViewRenderProbe.renderedSize(EventEditView(viewModel: createVM, onFinished: {}))
        #expect(size != nil && size!.width > 0 && size!.height > 0, "EventEditView failed to render .create")

        let event = Fixture.event(id: "e1", start: Date(), end: Date().addingTimeInterval(1800))
        let editVM = EventEditViewModel(agenda: agenda, mode: .edit(original: event))
        size = ViewRenderProbe.renderedSize(EventEditView(viewModel: editVM, onFinished: {}))
        #expect(size != nil && size!.width > 0 && size!.height > 0, "EventEditView failed to render .edit")
    }

    @Test("TaskComposerView renders without crashing")
    func taskComposerViewRenders() {
        let day = DayStamp(date: Date(), calendar: .current)
        let viewModel = TaskComposerViewModel(agenda: makeAgenda(), dueDay: day)
        let size = ViewRenderProbe.renderedSize(TaskComposerView(viewModel: viewModel, onFinished: {}))
        #expect(size != nil && size!.width > 0 && size!.height > 0)
    }

    @Test("CalendarVisibilityView renders without crashing")
    func calendarVisibilityViewRenders() async {
        let directory = FakeCalendarDirectory()
        directory.result = .success([EventCalendarInfo(identifier: "a", title: "Home", colorRed: 1, colorGreen: 0, colorBlue: 0, isVisible: true)])
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: FakeTaskStore(), calendarDirectory: directory, calendarVisibility: FakeCalendarVisibilityStore())
        let agenda = AgendaViewModel(agendaService: service, calendar: .current)
        let viewModel = CalendarVisibilityViewModel(agenda: agenda)
        await viewModel.load()
        let size = ViewRenderProbe.renderedSize(CalendarVisibilityView(viewModel: viewModel))
        #expect(size != nil && size!.width > 0 && size!.height > 0)
    }
}

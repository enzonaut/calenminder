import Testing
import Foundation
@testable import Calenminder
@testable import CalenminderKit

@MainActor
struct CalendarVisibilityViewModelTests {
    private func makeAgenda(directory: FakeCalendarDirectory, visibility: FakeCalendarVisibilityStore) -> AgendaViewModel {
        let service = AgendaService(
            eventStore: FakeEventStore(), taskStore: FakeTaskStore(),
            calendarDirectory: directory, calendarVisibility: visibility
        )
        return AgendaViewModel(agendaService: service, calendar: .current)
    }

    @Test("DW-4.3/DW-4.2: load() lists calendars with their current visibility")
    func loadListsCalendarsWithVisibility() async {
        let directory = FakeCalendarDirectory()
        directory.result = .success([
            EventCalendarInfo(identifier: "a", title: "Home", colorRed: 1, colorGreen: 0, colorBlue: 0, isVisible: true),
        ])
        let visibility = FakeCalendarVisibilityStore()
        let viewModel = CalendarVisibilityViewModel(agenda: makeAgenda(directory: directory, visibility: visibility))

        await viewModel.load()

        #expect(viewModel.calendars.map(\.title) == ["Home"])
        #expect(viewModel.calendars.first?.isVisible == true)
    }

    @Test("DW-4.2: setVisible(false) hides a calendar and the change persists")
    func setVisibleFalseHidesCalendar() async {
        let directory = FakeCalendarDirectory()
        directory.result = .success([
            EventCalendarInfo(identifier: "a", title: "Home", colorRed: 1, colorGreen: 0, colorBlue: 0, isVisible: true),
        ])
        let visibility = FakeCalendarVisibilityStore()
        let viewModel = CalendarVisibilityViewModel(agenda: makeAgenda(directory: directory, visibility: visibility))
        await viewModel.load()

        await viewModel.setVisible(false, calendarIdentifier: "a")

        #expect(viewModel.calendars.first?.isVisible == false)
        #expect(visibility.isVisible(calendarIdentifier: "a") == false)
    }

    @Test("load() surfaces a directory error")
    func loadSurfacesDirectoryError() async {
        let directory = FakeCalendarDirectory()
        directory.result = .failure(TestError.boom)
        let viewModel = CalendarVisibilityViewModel(agenda: makeAgenda(directory: directory, visibility: FakeCalendarVisibilityStore()))

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
    }
}

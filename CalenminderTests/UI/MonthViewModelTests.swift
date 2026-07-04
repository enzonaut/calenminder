import Testing
import Foundation
@testable import Calenminder
@testable import CalenminderKit

/// DW-F2.2: Month view's view model - grid/summary loading, today-highlight
/// scoping, and paging.
@MainActor
struct MonthViewModelTests {
    let cal = Fixture.calendar("America/New_York")

    private func makeViewModel(
        events: FakeEventStore = FakeEventStore(),
        tasks: FakeTaskStore = FakeTaskStore(),
        month: MonthStamp? = nil,
        now: @escaping () -> Date = { Fixture.calendar("America/New_York").date(from: DateComponents(year: 2026, month: 7, day: 3))! }
    ) -> MonthViewModel {
        let service = AgendaService(eventStore: events, taskStore: tasks)
        return MonthViewModel(agendaService: service, month: month, calendar: cal, now: now)
    }

    @Test("DW-F2.2: load() populates the grid and per-day summaries from the agenda service")
    func test_DW_F2_2_loadPopulatesGridAndSummaries() async {
        let events = FakeEventStore()
        events.events = [Fixture.event(id: "e1", start: Fixture.date(cal, 2026, 7, 10, 9), end: Fixture.date(cal, 2026, 7, 10, 10))]
        let viewModel = makeViewModel(events: events, month: MonthStamp(year: 2026, month: 7))

        await viewModel.load()

        #expect(!viewModel.grid.isEmpty)
        #expect(viewModel.summaries[DayStamp(year: 2026, month: 7, day: 10)]?.hasEvents == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("DW-F2.2: today is only meaningful when the displayed month actually contains it")
    func test_DW_F2_2_todayHighlightOnlyWhenMonthContainsToday() async {
        // now() is fixed to 2026-07-03; a July 2026 view model's `today`
        // matches its own grid, an August 2026 one does not.
        let julyViewModel = makeViewModel(month: MonthStamp(year: 2026, month: 7))
        #expect(julyViewModel.today == DayStamp(year: 2026, month: 7, day: 3))
        let julyDays = julyViewModel.grid.flatMap { $0 }.compactMap { $0 }
        #expect(julyDays.contains(julyViewModel.today))

        let augustViewModel = makeViewModel(month: MonthStamp(year: 2026, month: 8))
        let augustDays = augustViewModel.grid.flatMap { $0 }.compactMap { $0 }
        #expect(!augustDays.contains(augustViewModel.today), "today (July 3) must not appear as a day cell in August's grid")
    }

    @Test("DW-F2.2: goToNextMonth/goToPreviousMonth page and reload")
    func pagingChangesMonthAndReloads() async {
        let viewModel = makeViewModel(month: MonthStamp(year: 2026, month: 7))
        await viewModel.load()

        viewModel.goToNextMonth()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(viewModel.month == MonthStamp(year: 2026, month: 8))

        viewModel.goToPreviousMonth()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(viewModel.month == MonthStamp(year: 2026, month: 7))
    }

    @Test("Paging across a year boundary rolls the year over correctly")
    func pagingAcrossYearBoundary() async {
        let viewModel = makeViewModel(month: MonthStamp(year: 2026, month: 12))
        await viewModel.load()

        viewModel.goToNextMonth()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.month == MonthStamp(year: 2027, month: 1))
    }

    @Test("DW-F2.2: an empty month has no per-day indicators")
    func emptyMonthHasNoIndicators() async {
        let viewModel = makeViewModel(month: MonthStamp(year: 2026, month: 9))

        await viewModel.load()

        #expect(viewModel.summaries.values.allSatisfy { !$0.hasEvents && $0.incompleteTaskCount == 0 })
    }

    @Test("load() surfaces a store error rather than a stale silent grid")
    func loadSurfacesStoreError() async {
        let events = FakeEventStore()
        events.fetchError = TestError.boom
        let viewModel = makeViewModel(events: events, month: MonthStamp(year: 2026, month: 7))

        await viewModel.load()

        #expect(viewModel.errorMessage != nil)
    }
}

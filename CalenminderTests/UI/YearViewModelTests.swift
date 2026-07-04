import Testing
import Foundation
@testable import Calenminder
@testable import CalenminderKit

/// DW-F2.3: Year view's view model - 12 mini-month grids, today derivation,
/// and year paging. No `AgendaService` dependency exists to fake: Year view
/// fetches nothing per-day, by construction.
@MainActor
struct YearViewModelTests {
    let cal = Fixture.calendar("America/New_York")

    @Test("DW-F2.3: produces exactly 12 month grids for the displayed year, in order")
    func test_DW_F2_3_yearProduces12MonthGrids() {
        let viewModel = YearViewModel(year: 2026, calendar: cal)

        let grids = viewModel.monthGrids

        #expect(grids.count == 12)
        #expect(grids.map(\.month.month) == Array(1...12))
        #expect(grids.allSatisfy { $0.month.year == 2026 })
    }

    @Test("DW-F2.3: each mini-month grid matches MonthGrid's own output (same layout, reused)")
    func miniMonthGridsMatchMonthGridDirectly() {
        let viewModel = YearViewModel(year: 2026, calendar: cal)

        let julyEntry = viewModel.monthGrids[6]

        #expect(julyEntry.grid == MonthGrid.rows(for: MonthStamp(year: 2026, month: 7), calendar: cal))
    }

    @Test("DW-F2.3: today is derived from the injected clock")
    func todayIsDerivedFromInjectedClock() {
        let viewModel = YearViewModel(year: 2026, calendar: cal, now: { Fixture.date(cal, 2026, 7, 3) })
        #expect(viewModel.today == DayStamp(year: 2026, month: 7, day: 3))
    }

    @Test("DW-F2.3: goToNextYear/goToPreviousYear page the displayed year")
    func test_DW_F2_3_yearPagingAdvancesAndRetreats() {
        let viewModel = YearViewModel(year: 2026, calendar: cal)

        viewModel.goToNextYear()
        #expect(viewModel.year == 2027)

        viewModel.goToPreviousYear()
        viewModel.goToPreviousYear()
        #expect(viewModel.year == 2025)
    }

    @Test("Defaults to the year of the injected clock's today when no year is given")
    func defaultsToCurrentYear() {
        let viewModel = YearViewModel(calendar: cal, now: { Fixture.date(cal, 2030, 1, 1) })
        #expect(viewModel.year == 2030)
    }
}

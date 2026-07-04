import Testing
import Foundation
@testable import Calenminder
@testable import CalenminderKit

/// DW-F2.5: view switcher, drill-down, and one-level back navigation. Pure
/// state, no I/O - no fakes/services needed.
@MainActor
struct CalendarNavigationViewModelTests {
    @Test("DW-F2.5: starts in .day mode by default")
    func startsInDayMode() {
        let navigation = CalendarNavigationViewModel()
        #expect(navigation.mode == .day)
        #expect(navigation.parentMode == nil)
    }

    @Test("DW-F2.5: switcher jumps directly between modes")
    func test_DW_F2_5_switcherJumpsBetweenModes() {
        let navigation = CalendarNavigationViewModel()

        navigation.showYear(2026)
        #expect(navigation.mode == .year(2026))

        navigation.showMonth(MonthStamp(year: 2026, month: 7))
        #expect(navigation.mode == .month(MonthStamp(year: 2026, month: 7)))

        navigation.showDay()
        #expect(navigation.mode == .day)
    }

    @Test("DW-F2.5: drilling down from Year to Month to Day tracks each step")
    func test_DW_F2_5_drillDownFromYearToMonthToDay() {
        let navigation = CalendarNavigationViewModel(mode: .year(2026))

        navigation.selectMonth(MonthStamp(year: 2026, month: 7))
        #expect(navigation.mode == .month(MonthStamp(year: 2026, month: 7)))
        #expect(navigation.parentMode == .year(2026))

        navigation.selectDay()
        #expect(navigation.mode == .day)
        #expect(navigation.parentMode == .month(MonthStamp(year: 2026, month: 7)))
    }

    @Test("DW-F2.5: back() returns to the drilled-from parent mode, one level")
    func test_DW_F2_5_backNavigationReturnsToParentMode() {
        let navigation = CalendarNavigationViewModel(mode: .year(2026))
        navigation.selectMonth(MonthStamp(year: 2026, month: 7))

        navigation.back()

        #expect(navigation.mode == .year(2026))
        #expect(navigation.parentMode == nil)
    }

    @Test("DW-F2.5: back() after reaching a mode via the switcher is a no-op")
    func test_DW_F2_5_switcherJumpDoesNotLeaveABackTarget() {
        let navigation = CalendarNavigationViewModel(mode: .year(2026))
        navigation.selectMonth(MonthStamp(year: 2026, month: 7)) // sets a parent
        navigation.showDay()                                     // switcher jump clears it
        #expect(navigation.parentMode == nil)

        navigation.back()

        #expect(navigation.mode == .day, "with no parent, back() must be a no-op")
    }

    @Test("back() called twice only undoes one level, not a deep history")
    func backOnlyUndoesOneLevel() {
        let navigation = CalendarNavigationViewModel(mode: .year(2026))
        navigation.selectMonth(MonthStamp(year: 2026, month: 7))
        navigation.selectDay()

        navigation.back()
        #expect(navigation.mode == .month(MonthStamp(year: 2026, month: 7)))

        navigation.back()
        #expect(navigation.mode == .month(MonthStamp(year: 2026, month: 7)), "no remembered parent past the one drill-down step - back() is a no-op here")
    }
}

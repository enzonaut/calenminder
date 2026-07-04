import Testing
import Foundation
@testable import Calenminder
@testable import CalenminderKit

/// DW-F2.4: the pure week-strip layout - correct 7-day window containing an
/// anchor day, locale first-weekday ordering, and a week that spans a month
/// boundary.
struct WeekLayoutTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        cal.firstWeekday = firstWeekday
        return cal
    }

    @Test("DW-F2.4: produces exactly 7 days")
    func producesSevenDays() {
        let days = WeekLayout.days(containing: DayStamp(year: 2026, month: 7, day: 3), calendar: calendar(firstWeekday: 1))
        #expect(days.count == 7)
    }

    @Test("DW-F2.4: the anchor day is a member of its own week")
    func anchorDayIsMemberOfItsWeek() {
        let anchor = DayStamp(year: 2026, month: 7, day: 3)
        let days = WeekLayout.days(containing: anchor, calendar: calendar(firstWeekday: 1))
        #expect(days.contains(anchor))
    }

    @Test("DW-F2.4: Sunday-first locale starts the week on Sunday")
    func sundayFirstLocaleStartsOnSunday() {
        // July 3, 2026 is a Friday; the Sunday-first week containing it runs Jun 28 - Jul 4.
        let days = WeekLayout.days(containing: DayStamp(year: 2026, month: 7, day: 3), calendar: calendar(firstWeekday: 1))
        #expect(days.first == DayStamp(year: 2026, month: 6, day: 28))
        #expect(days.last == DayStamp(year: 2026, month: 7, day: 4))
    }

    @Test("DW-F2.4: Monday-first locale starts the same week on Monday")
    func mondayFirstLocaleStartsOnMonday() {
        let days = WeekLayout.days(containing: DayStamp(year: 2026, month: 7, day: 3), calendar: calendar(firstWeekday: 2))
        #expect(days.first == DayStamp(year: 2026, month: 6, day: 29))
        #expect(days.last == DayStamp(year: 2026, month: 7, day: 5))
    }

    @Test("DW-F2.4: a week spanning two months carries both months' DayStamps correctly")
    func weekSpanningTwoMonthsCarriesBothMonths() {
        // Jun 28 - Jul 4, 2026 spans June/July - already exercised above, but
        // assert explicitly on the month boundary itself.
        let days = WeekLayout.days(containing: DayStamp(year: 2026, month: 7, day: 1), calendar: calendar(firstWeekday: 1))
        let months = Set(days.map { MonthStamp(containing: $0) })
        #expect(months.contains(MonthStamp(year: 2026, month: 6)))
        #expect(months.contains(MonthStamp(year: 2026, month: 7)))
    }

    @Test("DW-F2.4: a week fully inside a DST-transition month is still exactly 7 civil days")
    func weekInsideDSTMonthIsStillSevenDays() {
        // 2026-03-08 is spring-forward day (23-hour civil day); the week
        // layout counts civil days, unaffected by that hour's absence.
        let days = WeekLayout.days(containing: DayStamp(year: 2026, month: 3, day: 8), calendar: calendar(firstWeekday: 1))
        #expect(days.count == 7)
        #expect(days.contains(DayStamp(year: 2026, month: 3, day: 8)))
    }

    // MARK: - Feature 5: shiftedDay - the pure period-shifting math behind
    // Week strip's chevron *and* swipe paging.

    @Test("DW-F5.2: shifting by +1 week moves the anchor exactly 7 civil days forward")
    func shiftedDayByOneWeekForwardMovesExactlySevenDays() {
        let shifted = WeekLayout.shiftedDay(
            from: DayStamp(year: 2026, month: 7, day: 3), byWeeks: 1, calendar: calendar(firstWeekday: 1)
        )
        #expect(shifted == DayStamp(year: 2026, month: 7, day: 10))
    }

    @Test("DW-F5.2: shifting by -1 week moves the anchor exactly 7 civil days back")
    func shiftedDayByOneWeekBackMovesExactlySevenDays() {
        let shifted = WeekLayout.shiftedDay(
            from: DayStamp(year: 2026, month: 7, day: 3), byWeeks: -1, calendar: calendar(firstWeekday: 1)
        )
        #expect(shifted == DayStamp(year: 2026, month: 6, day: 26))
    }

    @Test("DW-F5.2: shifting by 0 weeks is a no-op")
    func shiftedDayByZeroWeeksIsNoOp() {
        let anchor = DayStamp(year: 2026, month: 7, day: 3)
        #expect(WeekLayout.shiftedDay(from: anchor, byWeeks: 0, calendar: calendar(firstWeekday: 1)) == anchor)
    }

    @Test("DW-F5.2: shifting forward across a year boundary rolls the year over correctly")
    func shiftedDayAcrossYearBoundaryRollsOver() {
        let shifted = WeekLayout.shiftedDay(
            from: DayStamp(year: 2026, month: 12, day: 30), byWeeks: 1, calendar: calendar(firstWeekday: 1)
        )
        #expect(shifted == DayStamp(year: 2027, month: 1, day: 6))
    }

    @Test("DW-F5.2: shifting a DST-transition week is still exactly 7 civil days later")
    func shiftedDayAcrossDSTIsStillSevenCivilDaysLater() {
        // 2026-03-08 is spring-forward day (23-hour civil day); the shift
        // counts civil days, unaffected by that hour's absence.
        let shifted = WeekLayout.shiftedDay(
            from: DayStamp(year: 2026, month: 3, day: 8), byWeeks: 1, calendar: calendar(firstWeekday: 1)
        )
        #expect(shifted == DayStamp(year: 2026, month: 3, day: 15))
    }

    @Test("DW-F5.2: the shifted-to week window contains the shifted day, exactly like any other anchor")
    func shiftedDayComposesWithDaysContaining() {
        let anchor = DayStamp(year: 2026, month: 7, day: 3)
        let nextWeekAnchor = WeekLayout.shiftedDay(from: anchor, byWeeks: 1, calendar: calendar(firstWeekday: 1))
        let nextWeekDays = WeekLayout.days(containing: nextWeekAnchor, calendar: calendar(firstWeekday: 1))
        #expect(nextWeekDays.count == 7)
        #expect(nextWeekDays.contains(nextWeekAnchor))
        // The two 7-day windows must be adjacent, non-overlapping weeks.
        let thisWeekDays = WeekLayout.days(containing: anchor, calendar: calendar(firstWeekday: 1))
        #expect(Set(thisWeekDays).isDisjoint(with: Set(nextWeekDays)))
    }
}

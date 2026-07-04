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
}

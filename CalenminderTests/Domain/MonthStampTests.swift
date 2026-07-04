import Testing
import Foundation
@testable import CalenminderKit

/// DW-F2.2/DW-F2.3: `MonthStamp`'s civil-date math - day counts (including
/// leap February), month-shift rollover, and the `DayWindow(month:)`
/// initializer it backs.
struct MonthStampTests {
    let cal = Fixture.calendar("America/New_York")

    @Test("DW-F2.2: numberOfDays is correct for 28/29/30/31-day months, including leap February")
    func numberOfDaysAcrossMonthLengths() {
        #expect(MonthStamp(year: 2026, month: 2).numberOfDays(in: cal) == 28) // non-leap Feb
        #expect(MonthStamp(year: 2028, month: 2).numberOfDays(in: cal) == 29) // leap Feb
        #expect(MonthStamp(year: 2026, month: 4).numberOfDays(in: cal) == 30)
        #expect(MonthStamp(year: 2026, month: 7).numberOfDays(in: cal) == 31)
    }

    @Test("DW-F2.2: numberOfDays is unaffected by a DST-transition month")
    func numberOfDaysAcrossDSTMonths() {
        // March 2026 (spring-forward) and November 2026 (fall-back) still
        // have their ordinary calendar day counts - DST changes a day's
        // duration, never how many days are in the month.
        #expect(MonthStamp(year: 2026, month: 3).numberOfDays(in: cal) == 31)
        #expect(MonthStamp(year: 2026, month: 11).numberOfDays(in: cal) == 30)
    }

    @Test("containing(day:) derives the correct month")
    func containingDayDerivesMonth() {
        let month = MonthStamp(containing: DayStamp(year: 2026, month: 7, day: 15))
        #expect(month == MonthStamp(year: 2026, month: 7))
    }

    @Test("adding(months:) rolls over year boundaries in both directions")
    func addingMonthsRollsOverYearBoundary() {
        let dec = MonthStamp(year: 2026, month: 12)
        #expect(dec.adding(months: 1, in: cal) == MonthStamp(year: 2027, month: 1))
        let jan = MonthStamp(year: 2026, month: 1)
        #expect(jan.adding(months: -1, in: cal) == MonthStamp(year: 2025, month: 12))
    }

    @Test("MonthStamp orders lexicographically across year boundaries")
    func ordersAcrossYearBoundary() {
        #expect(MonthStamp(year: 2025, month: 12) < MonthStamp(year: 2026, month: 1))
    }

    @Test("DayWindow(month:calendar:) covers exactly the month's days, half-open")
    func dayWindowMonthCoversWholeMonth() {
        let window = DayWindow(month: MonthStamp(year: 2026, month: 7), calendar: cal)!
        #expect(DayStamp(date: window.start, calendar: cal) == DayStamp(year: 2026, month: 7, day: 1))
        // end is exclusive: the first instant of August.
        #expect(DayStamp(date: window.end, calendar: cal) == DayStamp(year: 2026, month: 8, day: 1))
    }

    @Test("DayWindow(month:calendar:) spans a leap February correctly")
    func dayWindowLeapFebruarySpansCorrectly() {
        let window = DayWindow(month: MonthStamp(year: 2028, month: 2), calendar: cal)!
        let lastCoveredDay = DayStamp(date: window.end.addingTimeInterval(-1), calendar: cal)
        #expect(lastCoveredDay == DayStamp(year: 2028, month: 2, day: 29))
    }
}

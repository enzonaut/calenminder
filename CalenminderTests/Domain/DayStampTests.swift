import Testing
import Foundation
@testable import CalenminderKit

/// DW-2.3: task due-day comparison across timezones and DST. `DayStamp` is a
/// civil date (no time-of-day), so comparisons never shift across a DST or
/// timezone boundary - the property that makes rollover correct.
struct DayStampTests {

    @Test("DW-2.3: due-day comparison is stable across the spring-forward DST day")
    func test_DW_2_3_taskDueDayAcrossDST() {
        // 2026-03-08 is a 23-hour civil day in US Eastern; comparison is unaffected.
        let mar7 = DayStamp(year: 2026, month: 3, day: 7)
        let mar8 = DayStamp(year: 2026, month: 3, day: 8)
        let mar9 = DayStamp(year: 2026, month: 3, day: 9)
        #expect(mar7 < mar8)
        #expect(mar8 < mar9)
        // A task due Mar 8 is overdue as of Mar 9 (dueDay < today).
        #expect(mar8 < mar9)
        #expect(!(mar9 < mar8))
    }

    @Test("DW-2.3: instants on either side of the spring-forward gap read as the same civil day")
    func test_DW_2_3_taskDueDayAcrossTimezone() {
        let eastern = Fixture.calendar("America/New_York")
        // 01:30 (EST, before the 02:00 gap) and 03:30 (EDT, after) are both Mar 8.
        let beforeGap = Fixture.date(eastern, 2026, 3, 8, 1, 30)
        let afterGap = Fixture.date(eastern, 2026, 3, 8, 3, 30)
        #expect(DayStamp(date: beforeGap, calendar: eastern) == DayStamp(year: 2026, month: 3, day: 8))
        #expect(DayStamp(date: afterGap, calendar: eastern) == DayStamp(year: 2026, month: 3, day: 8))
    }

    @Test("The same instant is a different civil day in different timezones")
    func sameInstantDiffersByTimezone() {
        // 2026-07-03 23:00 in Los Angeles is 2026-07-04 02:00 in New York.
        let la = Fixture.calendar("America/Los_Angeles")
        let ny = Fixture.calendar("America/New_York")
        let instant = Fixture.date(la, 2026, 7, 3, 23, 0)
        #expect(DayStamp(date: instant, calendar: la) == DayStamp(year: 2026, month: 7, day: 3))
        #expect(DayStamp(date: instant, calendar: ny) == DayStamp(year: 2026, month: 7, day: 4))
    }

    @Test("DayStamp orders lexicographically across month and year boundaries")
    func ordersAcrossMonthAndYearBoundaries() {
        #expect(DayStamp(year: 2025, month: 12, day: 31) < DayStamp(year: 2026, month: 1, day: 1))
        #expect(DayStamp(year: 2026, month: 1, day: 31) < DayStamp(year: 2026, month: 2, day: 1))
    }

    @Test("startOfDay round-trips a DayStamp back through a calendar")
    func startOfDayRoundTrips() {
        let cal = Fixture.calendar("America/New_York")
        let stamp = DayStamp(year: 2026, month: 7, day: 3)
        let start = stamp.startOfDay(in: cal)
        #expect(start != nil)
        #expect(DayStamp(date: start!, calendar: cal) == stamp)
        // It is genuinely the start of the day.
        #expect(cal.component(.hour, from: start!) == 0)
    }

    @Test("DayStamp constructed from a Date matches its civil components")
    func constructedFromDateMatchesComponents() {
        let cal = Fixture.calendar("America/New_York")
        let date = Fixture.date(cal, 2026, 7, 3, 14, 30)
        #expect(DayStamp(date: date, calendar: cal) == DayStamp(year: 2026, month: 7, day: 3))
    }
}

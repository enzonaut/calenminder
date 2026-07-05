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

    // MARK: - DW-B2.1: weekly-recurrence anchor snapping (`nextOccurrence`)

    @Test("DW-B2.1: the user's bug scenario - a Monday task composed on a Sunday snaps to the next Monday")
    func test_DW_B2_1_sundayToNextMonday() {
        let cal = Fixture.calendar("America/New_York")
        // 2026-07-05 is a Sunday; weekly Monday = Gregorian weekday 2.
        let sunday = DayStamp(year: 2026, month: 7, day: 5)
        #expect(sunday.nextOccurrence(ofWeekday: 2, in: cal) == DayStamp(year: 2026, month: 7, day: 6))
    }

    @Test("DW-B2.1: same-weekday snapping keeps the day (composing 'every Monday' on a Monday)")
    func test_DW_B2_1_sameWeekdayKeepsDay() {
        let cal = Fixture.calendar("America/New_York")
        // 2026-07-06 is a Monday; snapping to Monday (2) must return itself.
        let monday = DayStamp(year: 2026, month: 7, day: 6)
        #expect(monday.nextOccurrence(ofWeekday: 2, in: cal) == monday)
    }

    @Test("DW-B2.1: snapping to a weekday earlier in the week advances a full week")
    func test_DW_B2_1_fullWeekWrap() {
        let cal = Fixture.calendar("America/New_York")
        // Monday 2026-07-06 snapping to Sunday (1) lands on the *next* Sunday.
        let monday = DayStamp(year: 2026, month: 7, day: 6)
        #expect(monday.nextOccurrence(ofWeekday: 1, in: cal) == DayStamp(year: 2026, month: 7, day: 12))
    }

    @Test("DW-B2.1: snapping is correct across the spring-forward DST week")
    func test_DW_B2_1_acrossDSTWeek() {
        let eastern = Fixture.calendar("America/New_York")
        // 2026-03-08 is the 23-hour spring-forward Sunday in US Eastern.
        // From Saturday 2026-03-07, snapping to Sunday (1) lands squarely on
        // that short day (day-granular arithmetic, not a fixed 86 400s hop)...
        let saturday = DayStamp(year: 2026, month: 3, day: 7)
        #expect(saturday.nextOccurrence(ofWeekday: 1, in: eastern) == DayStamp(year: 2026, month: 3, day: 8))
        // ...and snapping to Monday (2) crosses the DST boundary to 2026-03-09.
        #expect(saturday.nextOccurrence(ofWeekday: 2, in: eastern) == DayStamp(year: 2026, month: 3, day: 9))
    }

    @Test("DW-B2.1: snapping is correct across a year boundary")
    func test_DW_B2_1_acrossYearBoundary() {
        let cal = Fixture.calendar("America/New_York")
        // Tuesday 2025-12-30 snapping to Thursday (5) crosses into 2026.
        let tuesday = DayStamp(year: 2025, month: 12, day: 30)
        #expect(tuesday.nextOccurrence(ofWeekday: 5, in: cal) == DayStamp(year: 2026, month: 1, day: 1))
    }

    @Test("A garbled (out-of-range) weekday degrades to nil rather than crashing")
    func nextOccurrenceRejectsOutOfRangeWeekday() {
        let cal = Fixture.calendar("America/New_York")
        let day = DayStamp(year: 2026, month: 7, day: 5)
        #expect(day.nextOccurrence(ofWeekday: 0, in: cal) == nil)
        #expect(day.nextOccurrence(ofWeekday: 8, in: cal) == nil)
    }
}

import Testing
import Foundation
@testable import Calenminder
@testable import CalenminderKit

/// DW-F2.2: month-grid layout - row/column counts across 28/29/30/31-day
/// months, locale first-weekday (Sunday vs Monday), and leap February.
struct MonthGridTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        cal.firstWeekday = firstWeekday
        return cal
    }

    @Test("DW-F2.2: every row has exactly 7 columns")
    func everyRowHasSevenColumns() {
        let rows = MonthGrid.rows(for: MonthStamp(year: 2026, month: 7), calendar: calendar(firstWeekday: 1))
        for row in rows {
            #expect(row.count == 7)
        }
    }

    @Test("DW-F2.2: total row count is between 4 and 6 whole weeks, for every month length")
    func rowCountIsBetweenFourAndSix() {
        let months: [MonthStamp] = [
            MonthStamp(year: 2026, month: 2),  // 28 days, non-leap
            MonthStamp(year: 2028, month: 2),  // 29 days, leap
            MonthStamp(year: 2026, month: 4),  // 30 days
            MonthStamp(year: 2026, month: 7),  // 31 days
        ]
        for month in months {
            let rows = MonthGrid.rows(for: month, calendar: calendar(firstWeekday: 1))
            #expect((4...6).contains(rows.count), "\(month) produced \(rows.count) rows")
        }
    }

    @Test("DW-F2.2: the grid contains exactly one DayStamp per calendar day of the month")
    func gridContainsExactlyOneCellPerDay() {
        let month = MonthStamp(year: 2026, month: 7) // 31 days
        let rows = MonthGrid.rows(for: month, calendar: calendar(firstWeekday: 1))
        let days = rows.flatMap { $0 }.compactMap { $0 }
        #expect(days.count == 31)
        #expect(Set(days.map(\.day)) == Set(1...31))
    }

    @Test("DW-F2.2: leap February 2028 produces exactly 29 day cells")
    func leapFebruaryProduces29DayCells() {
        let rows = MonthGrid.rows(for: MonthStamp(year: 2028, month: 2), calendar: calendar(firstWeekday: 1))
        let days = rows.flatMap { $0 }.compactMap { $0 }
        #expect(days.count == 29)
    }

    @Test("DW-F2.2: a DST-transition month (March 2026) still lays out its ordinary day count")
    func dstMonthLaysOutOrdinaryDayCount() {
        let rows = MonthGrid.rows(for: MonthStamp(year: 2026, month: 3), calendar: calendar(firstWeekday: 1))
        let days = rows.flatMap { $0 }.compactMap { $0 }
        #expect(days.count == 31)
    }

    @Test("DW-F2.2: Sunday-first locale places day 1 in the correct column for a month starting midweek")
    func sundayFirstLocalePlacesDay1Correctly() {
        // July 1, 2026 is a Wednesday (weekday 4, 1-indexed Sun=1).
        let rows = MonthGrid.rows(for: MonthStamp(year: 2026, month: 7), calendar: calendar(firstWeekday: 1))
        // Sunday-first: Sun, Mon, Tue, Wed... day 1 lands in column index 3.
        #expect(rows[0][3] == DayStamp(year: 2026, month: 7, day: 1))
        #expect(rows[0][0] == nil)
        #expect(rows[0][1] == nil)
        #expect(rows[0][2] == nil)
    }

    @Test("DW-F2.2: Monday-first locale shifts day 1 into a different column for the same month")
    func mondayFirstLocaleShiftsDay1Column() {
        // Same month, firstWeekday = Monday (2): Mon, Tue, Wed... day 1 (a
        // Wednesday) now lands in column index 2, not 3.
        let rows = MonthGrid.rows(for: MonthStamp(year: 2026, month: 7), calendar: calendar(firstWeekday: 2))
        #expect(rows[0][2] == DayStamp(year: 2026, month: 7, day: 1))
        #expect(rows[0][0] == nil)
        #expect(rows[0][1] == nil)
    }

    @Test("DW-F2.2: a month whose 1st falls on the locale's first weekday has zero leading blanks")
    func monthStartingOnFirstWeekdayHasNoLeadingBlanks() {
        // August 1, 2026 is a Saturday (weekday 7). With firstWeekday = 7,
        // day 1 is the very first cell.
        let rows = MonthGrid.rows(for: MonthStamp(year: 2026, month: 8), calendar: calendar(firstWeekday: 7))
        #expect(rows[0][0] == DayStamp(year: 2026, month: 8, day: 1))
    }

    @Test("Trailing blanks pad the final row to exactly 7 columns")
    func trailingBlanksPadFinalRow() {
        let rows = MonthGrid.rows(for: MonthStamp(year: 2026, month: 7), calendar: calendar(firstWeekday: 1))
        let lastRow = rows[rows.count - 1]
        #expect(lastRow.count == 7)
        // Some entries in the final row may be nil padding; the row itself is
        // still full width.
    }
}

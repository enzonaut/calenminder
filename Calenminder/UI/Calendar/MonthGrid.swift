import Foundation
import CalenminderKit

/// Pure month-grid layout: turns a `MonthStamp` into rows of exactly 7
/// columns, sized to whole weeks (4-6 rows), honoring `calendar.firstWeekday`.
/// Shared verbatim by Month view (one grid) and Year view (12 grids, no
/// indicators) - no I/O, no view-model state, just data-shape computation.
///
/// Padding cells (days from the adjacent month needed to fill a leading or
/// trailing partial week) are `nil`, not real `DayStamp`s from that other
/// month: this keeps the grid's own data need scoped to exactly its month (no
/// adjacent-month fetch required for the grid shape itself), and every DW-F2.2
/// requirement (row/column counts, first-weekday, leap Feb, today highlight,
/// indicators, day tap) is satisfiable with blank padding alone.
enum MonthGrid {
    static func rows(for month: MonthStamp, calendar: Calendar) -> [[DayStamp?]] {
        let daysInMonth = month.numberOfDays(in: calendar)
        guard let firstDayDate = month.firstDay.startOfDay(in: calendar) else { return [] }

        // 1...7, Sunday...Saturday - Foundation's `.weekday` convention, which
        // also matches `calendar.firstWeekday`'s own numbering.
        let firstWeekdayOfMonth = calendar.component(.weekday, from: firstDayDate)
        let leadingBlanks = (firstWeekdayOfMonth - calendar.firstWeekday + 7) % 7

        var cells: [DayStamp?] = Array(repeating: nil, count: leadingBlanks)
        cells.append(contentsOf: (1...daysInMonth).map { DayStamp(year: month.year, month: month.month, day: $0) })
        let trailingBlanks = (7 - cells.count % 7) % 7
        cells.append(contentsOf: Array(repeating: nil, count: trailingBlanks))

        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}

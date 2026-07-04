import Foundation

/// A calendar month with no day component - a civil year/month, the Year/Month
/// view analogue of `DayStamp`.
///
/// Kept as its own type rather than a `DayStamp` with `day` pinned to 1: a
/// `DayStamp` whose `day` is sometimes meaningful and sometimes a placeholder
/// invites bugs (e.g. comparing `DayStamp(day: 1)` against `DayStamp(day: 15)`
/// for "the same month"). `MonthStamp` hides all days-in-month/leap-year/DST
/// math behind `numberOfDays(in:)`, reused identically by Year view's 12
/// mini-months and Month view's single grid.
public struct MonthStamp: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// The month `day` falls in.
    public init(containing day: DayStamp) {
        self.init(year: day.year, month: day.month)
    }

    /// The 1st civil day of this month.
    public var firstDay: DayStamp {
        DayStamp(year: year, month: month, day: 1)
    }

    public static func < (lhs: MonthStamp, rhs: MonthStamp) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// 28-31, Gregorian-correct including leap February. Delegates entirely to
    /// `Calendar.range(of:in:for:)` rather than hand-rolled leap-year logic -
    /// day-count based, so it is also immune to DST (which only ever changes a
    /// day's *duration*, never how many days a month has).
    public func numberOfDays(in calendar: Calendar) -> Int {
        guard
            let start = firstDay.startOfDay(in: calendar),
            let range = calendar.range(of: .day, in: .month, for: start)
        else { return 30 } // Pathological calendar only; never hit for Gregorian.
        return range.count
    }

    /// This month shifted by `value` months (negative to go back), carrying
    /// year rollover for free via `DateComponents` arithmetic.
    public func adding(months value: Int, in calendar: Calendar) -> MonthStamp {
        guard
            let start = firstDay.startOfDay(in: calendar),
            let shifted = calendar.date(byAdding: .month, value: value, to: start)
        else { return self }
        return MonthStamp(containing: DayStamp(date: shifted, calendar: calendar))
    }
}

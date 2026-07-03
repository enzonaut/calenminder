import Foundation

/// A calendar day with no time component - a civil date (year/month/day).
///
/// Tasks are day-scoped: "do this sometime today" has no time-of-day, so a
/// task due July 3 is due July 3 in every timezone. Modeling a due day as a
/// civil date rather than a `Date` instant makes due-day comparison inherently
/// timezone- and DST-safe: there is no time-of-day to shift across a boundary.
public struct DayStamp: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The civil day that `date` falls on, as read in `calendar` (which carries
    /// the timezone). The same instant is a different `DayStamp` in different
    /// timezones - which is correct: "which day is it" is a per-timezone question.
    public init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        // Gregorian year/month/day are always present for a valid date; the
        // fallbacks keep this total rather than trapping on a pathological calendar.
        self.init(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    /// The instant at the start of this civil day in `calendar`'s timezone,
    /// or `nil` if the components do not resolve to a real date in `calendar`.
    public func startOfDay(in calendar: Calendar) -> Date? {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        return calendar.date(from: c)
    }

    public static func < (lhs: DayStamp, rhs: DayStamp) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

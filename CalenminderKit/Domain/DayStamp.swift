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

    /// The civil day on or after `self` whose Gregorian weekday is `weekday`
    /// (Sunday = 1 ... Saturday = 7, matching `Calendar.component(.weekday:)`
    /// and `TaskRecurrence.weekly(weekday:)`). Same-day counts: when `self`
    /// already falls on `weekday`, `self` is returned unchanged - so anchoring
    /// "every Monday" on a Monday keeps that Monday, while anchoring it on a
    /// Sunday advances one day to the next Monday.
    ///
    /// This is the snap that makes a weekly-recurring task's first occurrence
    /// land on its own weekday rather than on whatever day it was created:
    /// EventKit advances a recurring reminder from its `dueDateComponents`
    /// anchor, so the anchor itself must already sit on the recurrence weekday.
    ///
    /// `nil` if `weekday` is out of range (a garbled weekday degrades to "no
    /// snap" rather than crashing, matching this codebase's graceful-garbled
    /// pattern) or if `self` does not resolve to a real date in `calendar`.
    /// Day-granular calendar arithmetic keeps this DST-safe (it advances by
    /// civil days, never a fixed 86 400s) and correct across month/year ends.
    public func nextOccurrence(ofWeekday weekday: Int, in calendar: Calendar) -> DayStamp? {
        guard (1...7).contains(weekday), let start = startOfDay(in: calendar) else { return nil }
        let current = calendar.component(.weekday, from: start)
        let delta = (weekday - current + 7) % 7
        guard let target = calendar.date(byAdding: .day, value: delta, to: start) else { return nil }
        return DayStamp(date: target, calendar: calendar)
    }

    public static func < (lhs: DayStamp, rhs: DayStamp) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

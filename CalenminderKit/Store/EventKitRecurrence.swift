import Foundation
import EventKit

/// Pure translation between `TaskRecurrence.weekly(weekday:)` and
/// `EKRecurrenceRule`. Both directions are plain value construction --
/// `EKRecurrenceRule` needs no `EKEventStore` to build or inspect -- so this
/// is unit-testable with real EventKit recurrence objects and no store at all.
enum EventKitRecurrence {
    /// Builds the weekly-by-one-weekday rule this app writes. `weekday` uses
    /// Gregorian numbering (Sunday = 1 ... Saturday = 7), matching
    /// `EKWeekday`'s raw values exactly. `nil` if `weekday` is out of range
    /// (defensive: a garbled weekday produces no recurrence rather than a
    /// crash, matching this codebase's "garbled input excluded gracefully"
    /// pattern).
    static func weeklyRule(weekday: Int) -> EKRecurrenceRule? {
        // `EKWeekday(rawValue:)` does not reliably return `nil` for an
        // out-of-range raw value on every SDK (observed: raw `0` produces a
        // non-nil `EKWeekday` that then crashes `EKRecurrenceDayOfWeek` with
        // an uncaught `NSException` -- "Invalid day number" -- deep inside
        // EventKit, which Swift cannot catch as a typed error). Validate the
        // range ourselves first so a garbled weekday always degrades to "no
        // recurrence" instead of crashing the process.
        guard (1...7).contains(weekday), let ekWeekday = EKWeekday(rawValue: weekday) else { return nil }
        return EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(ekWeekday)],
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
    }

    /// Reduces a reminder's recurrence rules down to "the weekday of the
    /// first rule, if it is a plain weekly-by-exactly-one-weekday rule".
    /// EventKit honors only one recurrence rule per reminder in practice and
    /// this app only ever writes the shape above; any additional rule, or a
    /// first rule that is not this shape, is silently dropped rather than
    /// modeled -- a reminder edited elsewhere into something more exotic
    /// must not crash the app, it just loses its recurrence badge.
    static func weeklyWeekday(from rules: [EKRecurrenceRule]?) -> Int? {
        guard let first = rules?.first, first.frequency == .weekly, first.interval == 1 else { return nil }
        guard let days = first.daysOfTheWeek, days.count == 1 else { return nil }
        return days[0].dayOfTheWeek.rawValue
    }

    /// Builds the daily rule this app writes: every day, no end date.
    static func dailyRule() -> EKRecurrenceRule {
        EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
    }

    /// Whether the first rule (only -- same "extra rules silently dropped"
    /// policy as `weeklyWeekday(from:)`) is a plain daily-every-1-day rule.
    static func isDaily(from rules: [EKRecurrenceRule]?) -> Bool {
        guard let first = rules?.first else { return false }
        return first.frequency == .daily && first.interval == 1
    }
}

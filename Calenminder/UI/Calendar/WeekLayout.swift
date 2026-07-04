import Foundation
import CalenminderKit

/// Pure week-strip layout: the 7 `DayStamp`s of the calendar week containing
/// `day`, ordered to start on `calendar.firstWeekday`. No I/O and no
/// view-model state - `WeekStripView` derives everything it shows from
/// `AgendaViewModel.day` plus this one function, so there is exactly one
/// source of truth for "which day is selected" (see the Feature 2 design
/// doc's week-strip design decision).
enum WeekLayout {
    static func days(containing day: DayStamp, calendar: Calendar) -> [DayStamp] {
        guard let anchor = day.startOfDay(in: calendar) else { return [day] }
        let weekdayOfAnchor = calendar.component(.weekday, from: anchor)
        let offsetToWeekStart = (weekdayOfAnchor - calendar.firstWeekday + 7) % 7
        guard let weekStart = calendar.date(byAdding: .day, value: -offsetToWeekStart, to: anchor) else { return [day] }

        return (0..<7).map { offset in
            let instant = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            return DayStamp(date: instant, calendar: calendar)
        }
    }

    /// The day exactly `weeks` calendar-weeks away from `day` - the pure
    /// period-shifting math behind Week strip's chevron *and* swipe paging
    /// (`WeekStripView.pageWeek`/`handleSwipeSettle`, which both call this
    /// same function rather than duplicating the day-shift arithmetic).
    ///
    ///     Find the instant at the start of `day` in `calendar`
    ///     If that instant exists:
    ///         Add (weeks * 7) days to it using `calendar`
    ///         If the shifted instant exists:
    ///             Return the DayStamp for that shifted instant, read in `calendar`
    ///     Return `day` unchanged (pathological-calendar fallback; never hit for Gregorian)
    ///
    /// `Calendar.date(byAdding:.day...)` (not hand-rolled arithmetic) keeps
    /// this DST-safe: adding civil days always normalizes across a
    /// spring-forward/fall-back boundary correctly.
    static func shiftedDay(from day: DayStamp, byWeeks weeks: Int, calendar: Calendar) -> DayStamp {
        guard
            let start = day.startOfDay(in: calendar),
            let shifted = calendar.date(byAdding: .day, value: weeks * 7, to: start)
        else { return day }
        return DayStamp(date: shifted, calendar: calendar)
    }
}

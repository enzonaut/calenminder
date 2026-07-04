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
}

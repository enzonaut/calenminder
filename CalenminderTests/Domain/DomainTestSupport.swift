import Foundation
@testable import CalenminderKit

/// Shared builders for Domain tests. Fixed calendars/timezones make the
/// DST and boundary tests deterministic.
enum Fixture {
    /// A Gregorian calendar pinned to `timeZone` (default US Eastern, which
    /// observes DST: spring-forward 2026-03-08 02:00, fall-back 2026-11-01 02:00).
    static func calendar(_ timeZone: String = "America/New_York") -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZone)!
        return cal
    }

    /// An instant from civil components read in `cal`'s timezone.
    static func date(
        _ cal: Calendar,
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute
        return cal.date(from: c)!
    }

    static func event(
        id: String = "evt",
        title: String = "Event",
        start: Date,
        end: Date,
        allDay: Bool = false,
        status: ParticipationStatus = .notInvited,
        occurrence: Date? = nil,
        calendar: String = "cal"
    ) -> Event {
        Event(
            externalIdentifier: id,
            occurrenceDate: occurrence ?? start,
            title: title,
            start: start,
            end: end,
            isAllDay: allDay,
            participation: status,
            calendarIdentifier: calendar
        )
    }

    static func task(
        id: String = "task",
        title: String = "Task",
        due: DayStamp,
        completed: Bool = false,
        recurrence: TaskRecurrence? = nil
    ) -> DayTask {
        DayTask(
            externalIdentifier: id,
            title: title,
            dueDay: due,
            isCompleted: completed,
            recurrence: recurrence
        )
    }
}

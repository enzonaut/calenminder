import Foundation

/// A half-open time range `[start, end)` scoped to a calendar (which carries the
/// timezone that gives "a day" its meaning). Used to fetch and filter the events
/// visible for a day (or span of days).
///
/// Membership is deliberately different for timed vs all-day events:
/// - Timed events use instant overlap, so an event ending exactly at midnight
///   belongs to the day it ends within, never the next day (half-open end).
/// - All-day events use civil-day intersection, so an all-day "July 3" appears
///   on July 3 regardless of the viewer's timezone offset.
public struct DayWindow: Equatable, Sendable {
    /// Inclusive lower bound.
    public let start: Date
    /// Exclusive upper bound.
    public let end: Date
    /// The calendar (and thus timezone) the window is expressed in.
    public let calendar: Calendar

    public init(start: Date, end: Date, calendar: Calendar) {
        self.start = start
        self.end = end
        self.calendar = calendar
    }

    /// The window covering a single civil `day` in `calendar`:
    /// `[startOfDay(day), startOfDay(day + 1))`. `nil` only if the day does not
    /// resolve to a real date in `calendar`.
    public init?(day: DayStamp, calendar: Calendar) {
        guard
            let start = day.startOfDay(in: calendar),
            let end = calendar.date(byAdding: .day, value: 1, to: start)
        else { return nil }
        self.init(start: start, end: end, calendar: calendar)
    }

    /// The window covering a whole civil `month` in `calendar`:
    /// `[startOfDay(month.firstDay), startOfDay(next month's 1st))`. `nil`
    /// only if the month's boundaries do not resolve to real dates in
    /// `calendar`. Used for the Feature 2 month-summary fetch: one multi-day
    /// window, never a per-day fetch loop (see `AgendaService.monthSummary`).
    public init?(month: MonthStamp, calendar: Calendar) {
        guard
            let start = month.firstDay.startOfDay(in: calendar),
            let end = calendar.date(byAdding: .month, value: 1, to: start)
        else { return nil }
        self.init(start: start, end: end, calendar: calendar)
    }

    /// Whether `event` is visible in this window.
    public func contains(_ event: Event) -> Bool {
        if event.isAllDay {
            return containsAllDay(event)
        }
        // Half-open instant overlap. An event touching only the exclusive `end`
        // (e.g. ending exactly at midnight) is not counted in the next window.
        return event.start < end && event.end > start
    }

    /// All-day membership by civil-day intersection: the event's day span
    /// `[startDay ... endDay]` must intersect the window's day span. All-day
    /// EventKit events use an exclusive end date (midnight of the day after the
    /// last covered day), so the last covered day is the day before `event.end`.
    private func containsAllDay(_ event: Event) -> Bool {
        let eventFirstDay = DayStamp(date: event.start, calendar: calendar)
        // The window's last covered civil day is the day before `end` (end is
        // exclusive). Step back one second to land inside the final day.
        let windowFirstDay = DayStamp(date: start, calendar: calendar)
        let windowLastDay = DayStamp(date: end.addingTimeInterval(-1), calendar: calendar)

        // Exclusive end -> last covered day is the day before `event.end`.
        let eventLastInstant = max(event.start, event.end.addingTimeInterval(-1))
        let eventLastDay = DayStamp(date: eventLastInstant, calendar: calendar)

        // Two inclusive day ranges intersect iff neither ends before the other starts.
        return eventFirstDay <= windowLastDay && eventLastDay >= windowFirstDay
    }
}

import Foundation
import WidgetKit

/// Why the widget cannot show real agenda content right now. A first-class
/// case (not a thrown error) because the widget process has nowhere to
/// present a thrown error - `.unavailable` IS the widget's error UI
/// (DW-5.4's permission-missing state).
public enum WidgetUnavailableReason: Error, Equatable, Sendable {
    /// Reminders access is not (yet, or no longer) full access - tasks
    /// cannot be read.
    case remindersAccessDenied
    /// Calendars access is not (yet, or no longer) usable for reading -
    /// events cannot be read.
    case calendarsAccessDenied
    /// Some other failure occurred loading the agenda (e.g. an underlying
    /// EventKit save/fetch error unrelated to permissions).
    case loadFailed
}

/// The events/tasks to render, already capped to a per-family row budget
/// with an overflow count for "+N more" - capping happens once, in
/// `WidgetTimelineAssembly`, so the view layer never needs its own limit
/// logic.
public struct WidgetAgendaSlate: Equatable, Sendable {
    public let events: [Event]
    public let eventOverflowCount: Int
    public let tasks: [DayTask]
    public let taskOverflowCount: Int

    public init(events: [Event], eventOverflowCount: Int, tasks: [DayTask], taskOverflowCount: Int) {
        self.events = events
        self.eventOverflowCount = eventOverflowCount
        self.tasks = tasks
        self.taskOverflowCount = taskOverflowCount
    }

    /// Nothing to show at all: no events, no tasks, and nothing overflowed
    /// past the cap either (a slate with only an overflow count still has
    /// content - the overflow line itself).
    public var isEmpty: Bool {
        events.isEmpty && eventOverflowCount == 0 && tasks.isEmpty && taskOverflowCount == 0
    }
}

/// One rendered state for the widget: either real content or the reason it
/// could not be loaded.
public enum WidgetAgendaContent: Equatable, Sendable {
    case unavailable(WidgetUnavailableReason)
    case available(WidgetAgendaSlate)
}

/// One WidgetKit timeline entry. Conforms to `TimelineEntry` directly
/// (`CalenminderKit` already links `WidgetKit.framework` for
/// `SystemWidgetReloader`) so this is usable as-is by
/// `CalenminderWidget`'s real `TimelineProvider`, with no widget-target-only
/// wrapper type needed - keeping the entire timeline-entry shape testable
/// here, in `CalenminderKit`, against fakes.
public struct WidgetAgendaEntry: TimelineEntry, Equatable, Sendable {
    public let date: Date
    /// The civil day this entry represents (today's entry vs. the
    /// midnight-boundary entry for tomorrow - see `WidgetTimelineAssembly`).
    public let day: DayStamp
    public let content: WidgetAgendaContent

    public init(date: Date, day: DayStamp, content: WidgetAgendaContent) {
        self.date = date
        self.day = day
        self.content = content
    }
}

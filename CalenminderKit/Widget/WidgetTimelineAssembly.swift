import Foundation

/// Pure assembly of everything time- and layout-shaped that a WidgetKit
/// timeline needs: capping an `AgendaSnapshot` to a family's row budget
/// (DW-5.4's overflow/empty states) and building the midnight-spanning pair
/// of entries (DW-5.3). No I/O, no `WidgetKit` family type, no clock other
/// than the `now`/`calendar` callers pass in - every branch is exercised by
/// fakes in `CalenminderTests`, exactly like `assembleAgenda` (Phase 2).
public enum WidgetTimelineAssembly {
    /// How many event/task rows a widget family has room for. Deliberately
    /// not `WidgetKit.WidgetFamily` itself - keeping this framework-free
    /// keeps the whole type testable with no widget host, and the one
    /// family -> budget mapping lives in `CalenminderWidget`'s
    /// `TimelineProvider`, the one place that actually knows about
    /// `WidgetFamily`.
    public enum RowBudget: Equatable, Sendable {
        /// Lock Screen `accessoryRectangular` - room for roughly two short
        /// text lines.
        case lockScreen
        /// Home Screen `systemSmall`.
        case homeScreenSmall
        /// Home Screen `systemMedium`.
        case homeScreenMedium

        public var maxEvents: Int {
            switch self {
            case .lockScreen: return 1
            case .homeScreenSmall: return 2
            case .homeScreenMedium: return 3
            }
        }

        public var maxTasks: Int {
            switch self {
            case .lockScreen: return 1
            case .homeScreenSmall: return 2
            case .homeScreenMedium: return 3
            }
        }
    }

    // PSEUDOCODE: slate(from:budget:)
    //   Take the first `budget.maxEvents` of the snapshot's (already
    //   ordered) events; whatever is left over is the event overflow count.
    //   Same for tasks with `budget.maxTasks`.
    //   Return a WidgetAgendaSlate of the capped lists + overflow counts.

    /// Caps `snapshot`'s already-ordered events/tasks to `budget`, producing
    /// the overflow counts DW-5.4 requires ("more items than rows ->
    /// overflow count").
    public static func slate(from snapshot: AgendaSnapshot, budget: RowBudget) -> WidgetAgendaSlate {
        let events = Array(snapshot.events.prefix(budget.maxEvents))
        let tasks = Array(snapshot.tasks.prefix(budget.maxTasks))
        return WidgetAgendaSlate(
            events: events,
            eventOverflowCount: snapshot.events.count - events.count,
            tasks: tasks,
            taskOverflowCount: snapshot.tasks.count - tasks.count
        )
    }

    /// Turns a loaded-or-failed snapshot (`WidgetContentLoader`'s `Result`)
    /// plus a row budget into the one `WidgetAgendaContent` the view layer
    /// renders - success caps and wraps in `.available`, failure passes the
    /// reason straight through as `.unavailable`.
    public static func content(from result: Result<AgendaSnapshot, WidgetUnavailableReason>, budget: RowBudget) -> WidgetAgendaContent {
        switch result {
        case .success(let snapshot):
            return .available(slate(from: snapshot, budget: budget))
        case .failure(let reason):
            return .unavailable(reason)
        }
    }

    // PSEUDOCODE: entries(today:tomorrow:now:calendar:)
    //   Compute today's DayStamp from `now` in `calendar`.
    //   Compute the start-of-today instant and start-of-tomorrow instant.
    //   If either cannot be resolved (pathological calendar) -> return just
    //     one entry, dated `now`, holding `today`'s content: still correct,
    //     just without a pre-built rollover entry.
    //   Otherwise return two entries in chronological order:
    //     1. dated `now`, day = today, content = `today`
    //     2. dated exactly at start-of-tomorrow, day = tomorrow, content =
    //        `tomorrow`
    //   WidgetKit displays whichever entry's date has most recently passed,
    //   so it swaps to entry 2 automatically the instant midnight arrives -
    //   no reload call needed for the swap itself (DW-5.3).

    /// Builds the midnight-spanning entry pair. `today`/`tomorrow` are
    /// already-assembled content for those two civil days (the caller
    /// fetches both up front - see `CalenminderWidget`'s
    /// `TimelineProvider`).
    public static func entries(
        today: WidgetAgendaContent,
        tomorrow: WidgetAgendaContent,
        now: Date,
        calendar: Calendar
    ) -> [WidgetAgendaEntry] {
        let todayStamp = DayStamp(date: now, calendar: calendar)
        guard
            let startOfToday = todayStamp.startOfDay(in: calendar),
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
        else {
            return [WidgetAgendaEntry(date: now, day: todayStamp, content: today)]
        }
        let tomorrowStamp = DayStamp(date: startOfTomorrow, calendar: calendar)
        return [
            WidgetAgendaEntry(date: now, day: todayStamp, content: today),
            WidgetAgendaEntry(date: startOfTomorrow, day: tomorrowStamp, content: tomorrow),
        ]
    }
}

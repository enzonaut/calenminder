import WidgetKit
import SwiftUI
import CalenminderKit

/// Loads and assembles the widget's timeline. Deliberately as thin as
/// possible: every real decision (which events/tasks pass the filter, how
/// many rows fit, where the midnight boundary falls) is delegated to
/// `CalenminderKit.WidgetContentLoader`/`WidgetTimelineAssembly`, which are
/// unit-tested against fakes. `CalenminderTests` cannot link this target at
/// all (an app-extension product cannot be linked into a unit-test bundle -
/// confirmed Phase 1), so anything with real logic left in this file would
/// be untestable; DW-5.1/DW-5.2 are instead verified by simulator
/// screenshot evidence, matching the Phase 1 spike's own verification
/// method.
struct AgendaTimelineProvider: TimelineProvider {
    typealias Entry = WidgetAgendaEntry

    func placeholder(in context: Context) -> WidgetAgendaEntry {
        Self.placeholderEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetAgendaEntry) -> Void) {
        if context.isPreview {
            completion(Self.placeholderEntry())
            return
        }
        Task {
            let entry = await Self.loadTodayEntry(family: context.family)
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetAgendaEntry>) -> Void) {
        Task {
            let entries = await Self.loadEntries(family: context.family)
            let reloadDate = entries.last?.date ?? Date().addingTimeInterval(3600)
            completion(Timeline(entries: entries, policy: .after(reloadDate)))
        }
    }

    // MARK: - Loading (glue only - see CalenminderKit for the real logic)

    private static func budget(for family: WidgetFamily) -> WidgetTimelineAssembly.RowBudget {
        switch family {
        case .accessoryRectangular: return .lockScreen
        case .systemMedium: return .homeScreenMedium
        default: return .homeScreenSmall
        }
    }

    private static func placeholderEntry() -> WidgetAgendaEntry {
        let calendar = Calendar.current
        let now = Date()
        let day = DayStamp(date: now, calendar: calendar)
        let slate = WidgetAgendaSlate(
            events: [Event(
                externalIdentifier: "placeholder-event", occurrenceDate: now, title: "Team sync",
                start: now, end: now.addingTimeInterval(1800), isAllDay: false,
                participation: .accepted, calendarIdentifier: "placeholder"
            )],
            eventOverflowCount: 0,
            tasks: [DayTask(externalIdentifier: "placeholder-task", title: "Water plants", dueDay: day, isCompleted: false)],
            taskOverflowCount: 0
        )
        return WidgetAgendaEntry(date: now, day: day, content: .available(slate))
    }

    private static func loadTodayEntry(family: WidgetFamily) async -> WidgetAgendaEntry {
        let calendar = Calendar.current
        let now = Date()
        let day = DayStamp(date: now, calendar: calendar)
        let agendaService = WidgetEnvironment.liveAgendaService()
        let result = await WidgetContentLoader.loadSnapshot(day: day, calendar: calendar, agendaService: agendaService)
        let content = WidgetTimelineAssembly.content(from: result, budget: budget(for: family))
        return WidgetAgendaEntry(date: now, day: day, content: content)
    }

    private static func loadEntries(family: WidgetFamily) async -> [WidgetAgendaEntry] {
        let calendar = Calendar.current
        let now = Date()
        let today = DayStamp(date: now, calendar: calendar)
        let widgetBudget = budget(for: family)
        let agendaService = WidgetEnvironment.liveAgendaService()

        guard
            let startOfToday = today.startOfDay(in: calendar),
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
        else {
            let result = await WidgetContentLoader.loadSnapshot(day: today, calendar: calendar, agendaService: agendaService)
            let content = WidgetTimelineAssembly.content(from: result, budget: widgetBudget)
            return [WidgetAgendaEntry(date: now, day: today, content: content)]
        }
        let tomorrow = DayStamp(date: startOfTomorrow, calendar: calendar)

        async let todayResult = WidgetContentLoader.loadSnapshot(day: today, calendar: calendar, agendaService: agendaService)
        async let tomorrowResult = WidgetContentLoader.loadSnapshot(day: tomorrow, calendar: calendar, agendaService: agendaService)

        let todayContent = WidgetTimelineAssembly.content(from: await todayResult, budget: widgetBudget)
        let tomorrowContent = WidgetTimelineAssembly.content(from: await tomorrowResult, budget: widgetBudget)

        return WidgetTimelineAssembly.entries(today: todayContent, tomorrow: tomorrowContent, now: now, calendar: calendar)
    }
}

struct AgendaWidget: Widget {
    let kind: String = "AgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgendaTimelineProvider()) { entry in
            AgendaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Agenda")
        .description("Today's events and tasks, with one-tap complete.")
        .supportedFamilies([.accessoryRectangular, .systemSmall, .systemMedium])
    }
}

import SwiftUI

/// Non-interactive row/state content for the widget surface. Shared
/// verbatim by `CalenminderWidget`'s real, interactive layout (which wraps
/// these in `Button(intent:)`/`Link` - primitives that must reference
/// `CompleteTaskIntent`/deep-link URLs declared in the widget extension
/// target itself, per the Phase 1 finding, so the *interactive* wrapper
/// cannot move here) and by this target's own pragmatic render tests
/// (`ViewRenderProbe`, mirroring the Phase 4 pattern in `ViewSmokeTests`) -
/// these visuals carry no interactivity, so nothing about testing them here
/// is a lie about what actually ships.
public struct EventRowContentView: View {
    public let event: Event

    public init(event: Event) {
        self.event = event
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(Self.timeText(for: event))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(event.title)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private static func timeText(for event: Event) -> String {
        event.isAllDay ? "All-day" : event.start.formatted(date: .omitted, time: .shortened)
    }
}

public struct TaskRowContentView: View {
    public let task: DayTask

    public init(task: DayTask) {
        self.task = task
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle")
                .font(.caption2)
            Text(task.title)
                .font(.caption)
                .lineLimit(1)
        }
    }
}

/// "+N more" line for whichever section (events or tasks) overflowed its
/// row budget.
public struct OverflowRowView: View {
    public let count: Int
    public let noun: String

    public init(count: Int, noun: String) {
        self.count = count
        self.noun = noun
    }

    public var body: some View {
        Text("+\(count) more \(noun)\(count == 1 ? "" : "s")")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

/// Nothing to show today: no events, no tasks.
public struct EmptyAgendaView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
            Text("All clear today")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}

/// The widget's permission-missing placeholder (DW-5.4).
public struct PermissionMissingView: View {
    public let reason: WidgetUnavailableReason

    public init(reason: WidgetUnavailableReason) {
        self.reason = reason
    }

    public var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "lock")
                .font(.caption)
            Text(Self.message(for: reason))
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }

    private static func message(for reason: WidgetUnavailableReason) -> String {
        switch reason {
        case .remindersAccessDenied: return "Open Calenminder to allow Reminders access"
        case .calendarsAccessDenied: return "Open Calenminder to allow Calendars access"
        case .loadFailed: return "Couldn't load your agenda"
        }
    }
}

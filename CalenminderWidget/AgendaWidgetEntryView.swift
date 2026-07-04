import SwiftUI
import WidgetKit
import CalenminderKit

/// The widget's real, interactive layout. Row *content* (`EventRowContentView`,
/// `TaskRowContentView`, `OverflowRowView`, `EmptyAgendaView`,
/// `PermissionMissingView`) is shared verbatim from `CalenminderKit` - see
/// that target's `WidgetAgendaViews.swift` doc comment for why. Only the
/// interaction wrapper lives here: per `docs/code-standards.md`, widget
/// interactivity is `Button`/`Toggle`/`Link`/`widgetURL` only (no gesture
/// modifiers - they silently no-op), and `Button(intent:)` must reference
/// `CompleteTaskIntent`, which per the Phase 1 finding can only be declared
/// in this target.
struct AgendaWidgetEntryView: View {
    let entry: WidgetAgendaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch entry.content {
        case .unavailable(let reason):
            PermissionMissingView(reason: reason)
        case .available(let slate) where slate.isEmpty:
            EmptyAgendaView()
        case .available(let slate):
            slateBody(slate)
        }
    }

    @ViewBuilder
    private func slateBody(_ slate: WidgetAgendaSlate) -> some View {
        VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 1 : 3) {
            ForEach(slate.events) { event in
                Link(destination: DeepLink.event(externalIdentifier: event.externalIdentifier, occurrenceDate: event.occurrenceDate).url) {
                    EventRowContentView(event: event)
                }
                .accessibilityIdentifier("widget-event-row-\(event.externalIdentifier)")
            }
            if slate.eventOverflowCount > 0 {
                OverflowRowView(count: slate.eventOverflowCount, noun: "event")
            }
            ForEach(slate.tasks) { task in
                Button(intent: CompleteTaskIntent(taskExternalIdentifier: task.externalIdentifier)) {
                    TaskRowContentView(task: task)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("widget-task-complete-\(task.externalIdentifier)")
            }
            if slate.taskOverflowCount > 0 {
                OverflowRowView(count: slate.taskOverflowCount, noun: "task")
            }
        }
    }
}

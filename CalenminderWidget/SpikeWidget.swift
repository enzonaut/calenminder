import WidgetKit
import SwiftUI

/// Phase 1 platform spike widget. Hardcoded, throwaway: proves whether a
/// `Button(intent:)` fired from the widget extension process can mark an
/// `EKReminder` complete (Phase 1's one unverified platform assumption).
/// Real widget UI/layout is Phase 5 scope.
///
/// Uses `WidgetSpikeCompleteIntent` (declared directly in this target, not
/// the `CalenminderIntents` framework) -- see that file's doc comment for
/// why: a framework-declared intent silently failed to fire from this same
/// widget button in this toolchain, confirmed empirically.
struct SpikeEntry: TimelineEntry {
    let date: Date
}

struct SpikeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry {
        SpikeEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) {
        completion(SpikeEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        completion(Timeline(entries: [SpikeEntry(date: .now)], policy: .never))
    }
}

struct SpikeWidgetView: View {
    var entry: SpikeEntry

    var body: some View {
        Button(intent: WidgetSpikeCompleteIntent()) {
            Label("Complete Spike", systemImage: "checkmark.circle")
        }
        .accessibilityIdentifier("spike-complete-button")
    }
}

struct SpikeWidget: Widget {
    let kind: String = "SpikeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SpikeTimelineProvider()) { entry in
            SpikeWidgetView(entry: entry)
        }
        .configurationDisplayName("Calenminder Spike")
        .description("Phase 1 spike: taps CompleteSpikeReminderIntent.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

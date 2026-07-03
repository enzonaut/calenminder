import AppIntents
@preconcurrency import EventKit
import CalenminderKit
import os

/// The Phase 1 spike's working `Button(intent:)` implementation.
///
/// **Finding recorded in the Execution Log:** an earlier version of this
/// intent lived in the shared `CalenminderIntents` framework (matching the
/// plan's target layout) and linked/embedded correctly, but the widget's
/// tap silently no-op'd -- `perform()` never ran. `linkd` (the App Intents
/// registry) logged `Missing: com.enzonaut.calenminder:CompleteSpikeReminderIntent`
/// even though the framework's own `Metadata.appintents` was present inside
/// the extension bundle: cross-module App Intents declared in a separate
/// framework are not discovered by the widget's interactive-button registry
/// in this toolchain. Declaring the intent directly inside the widget
/// extension target (this file) resolved it -- confirmed by a real tap
/// producing `perform()` execution, a completed `EKReminder`, and a log
/// line, verified twice.
///
/// This is why the app's real `CompleteTaskIntent` (Phase 5) should be
/// declared directly in `CalenminderWidget`, not in `CalenminderIntents`.
/// `CalenminderIntents` still stands as scaffolding per this phase's scope
/// (see `CalenminderIntents/CompleteSpikeReminderIntent.swift`, kept
/// un-wired as documentation of the finding above), but Phase 5 should not
/// assume a shared-framework intent will fire from a widget button without
/// first re-verifying whatever registration workaround it attempts.
///
/// PSEUDOCODE:
///   Check current Reminders authorization status.
///   If not full access -> outcome = accessDenied.
///   Else: find the spike list by name; if missing -> listNotSeeded.
///   Else: predicate-fetch incomplete reminders in that list (async).
///   Find the reminder by known title; if missing -> reminderNotFound.
///   Else: set isCompleted = true, save; success or saveFailed.
///   Log the outcome and publish it to the App Group for the app's status
///   screen to display (screenshot evidence).
struct WidgetSpikeCompleteIntent: AppIntent {
    static var title: LocalizedStringResource { "Complete Spike Reminder" }

    private static let logger = Logger(
        subsystem: "com.enzonaut.calenminder.spike",
        category: "WidgetSpikeCompleteIntent"
    )

    static let outcomeDefaultsKey = "spike.lastOutcome"
    static let outcomeTimestampDefaultsKey = "spike.lastOutcomeAt"

    enum Outcome: String {
        case accessDenied, listNotSeeded, reminderNotFound, saveFailed, success
    }

    init() {}

    func perform() async throws -> some IntentResult {
        let outcome = await Self.completeSpikeReminder()
        Self.logger.log("spike outcome: \(outcome.rawValue, privacy: .public)")
        AppGroup.sharedDefaults?.set(outcome.rawValue, forKey: Self.outcomeDefaultsKey)
        AppGroup.sharedDefaults?.set(Date(), forKey: Self.outcomeTimestampDefaultsKey)
        return .result()
    }

    static func completeSpikeReminder(store: EKEventStore = EKEventStore()) async -> Outcome {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            return .accessDenied
        }
        guard let list = store.calendars(for: .reminder).first(where: { $0.title == SpikeConfig.listName }) else {
            return .listNotSeeded
        }

        let predicate = store.predicateForReminders(in: [list])
        let reminders = await withCheckedContinuation { (continuation: CheckedContinuation<[EKReminder], Never>) in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        guard let reminder = reminders.first(where: { $0.title == SpikeConfig.reminderTitle && !$0.isCompleted }) else {
            return .reminderNotFound
        }

        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            return .success
        } catch {
            logger.error("save failed: \(error.localizedDescription, privacy: .public)")
            return .saveFailed
        }
    }
}

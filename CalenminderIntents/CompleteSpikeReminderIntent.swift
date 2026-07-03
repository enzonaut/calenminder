import AppIntents
@preconcurrency import EventKit
import CalenminderKit
import os

/// Phase 1 platform spike, kept **unwired from the widget UI** as
/// documentation of a finding: this type is functionally identical to
/// `CalenminderWidget.WidgetSpikeCompleteIntent`, but declared in this
/// separate `CalenminderIntents` framework (the plan's original "shared
/// intents target" placement) instead of directly in the widget extension
/// target. When a `Button(intent:)` pointed at this type, the tap was
/// absorbed by the button but `perform()` never ran -- `linkd` (the App
/// Intents registry) reported the action as `Missing`, confirmed via
/// `log show`, even though the framework's own `Metadata.appintents` was
/// present inside the extension bundle. See
/// `CalenminderWidget/WidgetSpikeCompleteIntent.swift` for the working
/// version and the full finding, recorded in the Execution Log for Phase 5.
///
/// `CalenminderIntents` itself still stands as scaffolding: the plan's
/// Phase 1 scope requires the target to exist. This file demonstrates the
/// target compiles and hosts a real `AppIntent` conformance; it is simply
/// not the type Phase 5's widget button should invoke without first
/// re-verifying cross-module registration works by then.
///
/// PSEUDOCODE (see discovery doc "Design Decisions" for the full write-up):
///   Check current Reminders authorization status.
///   If not full access -> record "access denied" outcome, return.
///   Fetch the spike list by name; if missing -> record "not seeded", return.
///   Predicate-fetch incomplete reminders in that list (async).
///   Find the reminder by known title; if missing -> record "not found", return.
///   Set isCompleted = true; save.
///   Record "success" or "save failed" outcome.
///
/// Outcome is written to both the unified log (subsystem
/// "com.enzonaut.calenminder.spike") and the App Group's shared
/// `UserDefaults`, so the spike run can be verified by log inspection
/// (`log show`) and by a screenshot of the app's status screen.
public struct CompleteSpikeReminderIntent: AppIntent {
    public static var title: LocalizedStringResource { "Complete Spike Reminder" }
    public static var description: IntentDescription {
        IntentDescription("Marks the Phase 1 spike reminder complete from the widget, with no app launch.")
    }

    private static let logger = Logger(
        subsystem: "com.enzonaut.calenminder.spike",
        category: "CompleteSpikeReminderIntent"
    )

    public init() {}

    public func perform() async throws -> some IntentResult {
        let outcome = await Self.completeSpikeReminder()
        Self.logger.log("spike outcome: \(outcome.rawValue, privacy: .public)")
        AppGroup.sharedDefaults?.set(outcome.rawValue, forKey: Self.outcomeDefaultsKey)
        AppGroup.sharedDefaults?.set(Date(), forKey: Self.outcomeTimestampDefaultsKey)
        return .result()
    }

    public static let outcomeDefaultsKey = "spike.lastOutcome"
    public static let outcomeTimestampDefaultsKey = "spike.lastOutcomeAt"

    public enum Outcome: String {
        case accessDenied
        case listNotSeeded
        case reminderNotFound
        case saveFailed
        case success
    }

    /// Performs the spike completion. Static + internal-testable so the
    /// unit-test target can exercise the "not found" and "list missing"
    /// branches against a real (but empty/unseeded) reminders store,
    /// without needing full Reminders access in CI.
    static func completeSpikeReminder(store: EKEventStore = EKEventStore()) async -> Outcome {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .fullAccess else {
            return .accessDenied
        }

        guard let list = store.calendars(for: .reminder).first(where: { $0.title == SpikeConfig.listName }) else {
            return .listNotSeeded
        }

        let predicate = store.predicateForReminders(in: [list])
        let reminders = await fetchReminders(matching: predicate, store: store)

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

    /// Wraps EventKit's completion-handler-only reminder fetch in `async`,
    /// per code-standards ("never block on synchronous-looking reminder
    /// fetches").
    private static func fetchReminders(matching predicate: NSPredicate, store: EKEventStore) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }
}

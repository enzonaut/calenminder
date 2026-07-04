import AppIntents
import CalenminderKit

/// Marks a task complete from a Lock Screen or Home Screen widget button
/// tap, with no app launch (DW-5.2).
///
/// Declared directly in this target, not `CalenminderIntents`: an App
/// Intent invoked by a widget's interactive `Button(intent:)` in a separate
/// framework never fires in this toolchain - confirmed empirically in the
/// Phase 1 spike (see the plan's Execution Log and
/// `docs/code-standards.md`). All real logic lives in
/// `AgendaService.completeTask(externalIdentifier:referenceDay:)`
/// (`CalenminderKit`, unit-tested with fakes) - this type is the thinnest
/// possible `AppIntent` shim over it, matching the Phase 1 spike's
/// precedent (`WidgetSpikeCompleteIntent` was likewise a thin shim over
/// logic that lived, and stayed testable, elsewhere).
///
/// `AgendaService.completeTask` already resolves the task by ID, treats a
/// deleted/already-completed task as a graceful no-op, swallows any store
/// failure into the same no-op, and always reloads widget timelines
/// afterward (DW-5.5) - `perform()` has nothing left to do but call it and
/// return success unconditionally, since a stale tap must never surface a
/// system error dialog.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource { "Complete Task" }
    static var description: IntentDescription {
        IntentDescription("Marks a Calenminder task complete without opening the app.")
    }

    @Parameter(title: "Task ID")
    var taskExternalIdentifier: String

    init() {
        self.taskExternalIdentifier = ""
    }

    init(taskExternalIdentifier: String) {
        self.taskExternalIdentifier = taskExternalIdentifier
    }

    func perform() async throws -> some IntentResult {
        let agendaService = WidgetEnvironment.liveAgendaService()
        let today = DayStamp(date: .now, calendar: .current)
        await agendaService.completeTask(externalIdentifier: taskExternalIdentifier, referenceDay: today)
        // Feature 3: the widget-intent path is the other "task mutation"
        // trigger (alongside the app's AgendaViewModel call sites) - update
        // regardless of whether completeTask actually did anything, same
        // reasoning as its own unconditional widget-timeline reload above.
        // See docs/code-standards.md / the Feature 3 discovery doc for the
        // documented (not empirically device-verified) verdict on
        // UNUserNotificationCenter.setBadgeCount from this process, and why
        // the design does not depend on that verdict either way: every
        // app foreground/background unconditionally recomputes the full
        // count from scratch, so even a silently-failed update here is
        // corrected the moment the app is next foregrounded or backgrounded.
        let badgeUpdater = WidgetEnvironment.liveBadgeUpdater(agendaService: agendaService)
        await badgeUpdater.updateBadge()
        return .result()
    }
}

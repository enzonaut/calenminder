import Foundation

/// This framework target exists because Phase 1 scaffolded it as the plan's
/// designated home for shared App Intents. Phase 1's empirical spike proved
/// that an App Intent invoked by a widget's interactive `Button(intent:)`
/// must be declared directly inside the *consuming widget extension target*
/// - a framework-declared one never fires (`linkd` reports it `Missing`,
/// even though the framework's own `Metadata.appintents` is present inside
/// the extension bundle). See `docs/code-standards.md` and the plan's
/// Execution Log for the full finding.
///
/// Phase 5's `CompleteTaskIntent` therefore lives in `CalenminderWidget`,
/// not here, and the Phase 1 spike's proof-of-concept
/// (`CompleteSpikeReminderIntent`) has been retired now that its finding is
/// fully documented elsewhere.
///
/// This target is kept scaffolded and empty rather than deleted: it may
/// still be viable for an App Intent invoked only from the app's own
/// process (Siri/Shortcuts, never a widget button), which no v1 requirement
/// needs and which was never tested. Re-verify cross-module registration
/// empirically before relying on it for anything widget-button-invoked.
enum CalenminderIntentsPlaceholder {}

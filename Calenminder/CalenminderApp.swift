import SwiftUI

/// App entry point. Builds the one production `AppEnvironment` (real
/// EventKit-backed `AgendaService`) and hands it to `ContentView`, the
/// composition root. Phase 1's raw `EKEventStore` permission request and
/// throwaway spike-reminder seeding are retired here - that file's own doc
/// comment marked it Phase-1-scope-only, superseded by `OnboardingViewModel`
/// (which requests the same two permissions through the real `AgendaService`
/// read path instead of a separate ad hoc call).
@main
struct CalenminderApp: App {
    private let environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            ContentView(environment: environment)
        }
    }
}

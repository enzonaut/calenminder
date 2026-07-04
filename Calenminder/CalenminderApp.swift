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

    init() {
        // Feature 3: BGTaskScheduler requires registration before the app
        // finishes launching; there is no separate AppDelegate in this
        // app's lifecycle, so `init()` (which runs before any scene is
        // presented) is the earliest available hook - the documented
        // substitute under a pure SwiftUI app lifecycle. An initial
        // `schedule()` right after registering means the very first launch
        // already has an opportunistic refresh queued, rather than waiting
        // for the first backgrounding.
        let scheduler = BadgeRefreshScheduler(badgeUpdater: environment.badgeUpdater)
        scheduler.register()
        scheduler.schedule()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(environment: environment)
        }
    }
}

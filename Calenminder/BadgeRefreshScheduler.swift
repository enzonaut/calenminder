import Foundation
import BackgroundTasks
import CalenminderKit

/// Thin seam over the two `BGTaskScheduler` methods `BadgeRefreshScheduler`
/// uses, so `register()`/`schedule()` are unit-testable via a fake -
/// `BGTaskScheduler` has no protocol of its own, and its `BGTask`/
/// `BGAppRefreshTask` family have no public initializer, so a real task
/// instance can never be constructed in a test. This seam only needs to
/// cover the two calls actually made; it does not attempt to cover the
/// launch-handler closure body, which is exercised by code review and
/// (opportunistically, on-device) by the system itself firing the real task.
protocol BackgroundTaskScheduling: AnyObject {
    @discardableResult
    func register(forTaskWithIdentifier identifier: String, using queue: DispatchQueue?, launchHandler: @escaping (BGTask) -> Void) -> Bool
    func submit(_ taskRequest: BGTaskRequest) throws
}

extension BGTaskScheduler: BackgroundTaskScheduling {}

/// Feature 3's opportunistic badge refresh: registers a `BGAppRefreshTask`
/// identifier and keeps resubmitting it so the icon badge has a chance to
/// stay fresh even while the app is never foregrounded (e.g. a task rolls
/// over to "overdue" purely due to the clock, with no user action). Purely
/// lifecycle/app-layer wiring - the actual counting/setting logic is
/// `CalenminderKit.BadgeUpdater`'s job, not this type's; this type only ever
/// decides *when* to ask it to run, matching `AgendaViewModel`'s existing
/// split between lifecycle triggers (app layer) and counting logic
/// (CalenminderKit).
///
/// `BGTaskScheduler` is an opportunistic scheduler: `earliestBeginDate` is a
/// floor, never a promise - iOS alone decides the actual cadence (based on
/// battery, usage patterns, Low Power Mode, etc.), typically well less than
/// once an hour in practice. This type only ever *requests*; it never
/// assumes the request runs on any particular schedule.
final class BadgeRefreshScheduler {
    /// Must match the identifier listed under the app's
    /// `BGTaskSchedulerPermittedIdentifiers` Info.plist key (`project.yml`) -
    /// a mismatch fails `register`/`submit` silently at runtime with no
    /// compile-time signal, which is why both are asserted to agree in
    /// `BadgeRefreshSchedulerTests`.
    static let taskIdentifier = "com.enzonaut.calenminder.badgeRefresh"

    private let badgeUpdater: BadgeUpdater
    private let scheduler: BackgroundTaskScheduling

    init(badgeUpdater: BadgeUpdater, scheduler: BackgroundTaskScheduling = BGTaskScheduler.shared) {
        self.badgeUpdater = badgeUpdater
        self.scheduler = scheduler
    }

    // PSEUDOCODE: register()
    //   Register the launch handler for taskIdentifier with the scheduler.
    //   When the handler fires with a task:
    //     Reschedule immediately (call schedule() again) - the opportunistic
    //     budget is single-shot per submission, so the very next thing this
    //     handler does is ask for another one, keeping the refresh
    //     self-renewing.
    //     If the task is not actually a BGAppRefreshTask, mark it
    //     unsuccessful and stop (defensive; should never happen for this
    //     identifier).
    //     Otherwise, run badgeUpdater.updateBadge() in its own Task, marking
    //     the BGAppRefreshTask completed (successfully) when it finishes;
    //     wire the task's expirationHandler to cancel that Task if iOS
    //     revokes the time budget first.

    /// Registers the launch handler. Must be called before the app finishes
    /// launching (from `CalenminderApp.init()` - there is no separate
    /// `AppDelegate` in this app, and `init()` is the earliest available
    /// hook, which is the documented-in-practice substitute for
    /// `BGTaskScheduler`'s "register before applicationDidFinishLaunching
    /// returns" requirement under the pure SwiftUI app lifecycle).
    func register() {
        scheduler.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            self?.schedule()
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            guard let badgeUpdater = self?.badgeUpdater else {
                refreshTask.setTaskCompleted(success: false)
                return
            }
            let work = Task {
                await badgeUpdater.updateBadge()
                refreshTask.setTaskCompleted(success: true)
            }
            refreshTask.expirationHandler = { work.cancel() }
        }
    }

    /// Submits (or resubmits) the opportunistic refresh request. Safe to
    /// call repeatedly and from anywhere (app background, right after
    /// registration, at the start of the launch handler itself) - a failed
    /// submission (unit-test host, no launch entitlement yet, the system's
    /// per-app budget already exhausted) is not an error this app has
    /// anywhere useful to show, so it is swallowed rather than propagated,
    /// matching `SystemBadgeSetter`'s posture on its own system-API calls.
    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? scheduler.submit(request)
    }
}

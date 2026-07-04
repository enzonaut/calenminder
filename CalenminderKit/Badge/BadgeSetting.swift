import Foundation
import UserNotifications

/// Feature 3's seam over the icon badge, abstracted so tests never touch the
/// real `UNUserNotificationCenter` (which requires a real notification
/// authorization prompt and has no meaningful behavior to assert on in a
/// unit-test host) - mirrors `WidgetReloading`'s split between a protocol and
/// `SystemWidgetReloader`.
///
/// Both methods are deliberately non-throwing: a denied or not-yet-determined
/// authorization state, or any failure talking to the system, must never
/// surface as an error anywhere above this seam (DW-F3.3 - "authorization
/// denial is a silent no-op"). Callers (`BadgeUpdater`) call both on every
/// single invocation, with no cached "already asked"/"already denied" state
/// of their own - that is what makes a later Settings-granted permission take
/// effect on the very next call, with no separate reconciliation path needed.
public protocol BadgeSetting: AnyObject {
    /// Requests badge authorization if (and only if) it has not yet been
    /// determined. A no-op - no system prompt, no delay - once the user has
    /// already answered (granted or denied), so callers can invoke this on
    /// every foreground/mutation without spamming a dialog.
    func requestAuthorizationIfNeeded() async
    /// Sets the icon badge to `count`. Safe to call regardless of
    /// authorization state - an unauthorized call is a harmless no-op at the
    /// OS level (the badge simply does not render), never a crash or thrown
    /// error.
    func applyBadgeCount(_ count: Int) async
}

/// Production `BadgeSetting`, backed by `UNUserNotificationCenter`. Uses the
/// iOS 16+ `setBadgeCount(_:)` async API directly (this app's minimum target
/// is iOS 17, per `docs/code-standards.md`), wrapped in `try?` so a denied
/// or unexpectedly-failing call degrades to "nothing changed" rather than
/// throwing.
public final class SystemBadgeSetter: BadgeSetting {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.badge])
    }

    public func applyBadgeCount(_ count: Int) async {
        try? await center.setBadgeCount(count)
    }
}

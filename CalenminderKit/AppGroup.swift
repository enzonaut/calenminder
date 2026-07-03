import Foundation

/// Cross-target constants shared by the app, widget extension, and intents
/// framework. `CalenminderKit` is the shared framework that lets code
/// (starting with this constant, later `Domain`/`Store`/`Agenda`) run
/// identically from the App process and the Widget Extension process.
public enum AppGroup {
    /// App Group container identifier. Must match the
    /// `com.apple.security.application-groups` entitlement on both the
    /// Calenminder app target and the CalenminderWidget extension target.
    public static let identifier = "group.com.enzonaut.calenminder"

    /// Shared `UserDefaults` suite backed by the App Group container.
    /// `nil` only if the App Group entitlement is missing or misconfigured.
    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}

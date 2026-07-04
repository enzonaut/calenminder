import Foundation

/// Pure, injectable data for the About section folded into the calendar-
/// settings sheet (`CalendarVisibilityView`). Deliberately holds no
/// `Bundle`/I/O itself - `fromBundle(_:)` is the one seam that reads a real
/// bundle's info dictionary, so unit tests can build instances from a plain
/// dictionary instead of needing the compiled app bundle (which is not what
/// `Bundle.main` resolves to inside the `CalenminderTests` process anyway).
///
/// Pseudocode:
///   Given an optional short-version string and an optional build string
///   If either is missing or empty, substitute "unknown" for that piece
///   Compose "Version <short> (<build>)" as the single display label
///   Carry the two fixed link URLs (GitHub repo, privacy policy) alongside it
struct AppAboutInfo: Equatable {
    static let githubURL = URL(string: "https://github.com/enzonaut/calenminder")!
    static let privacyPolicyURL = URL(string: "https://github.com/enzonaut/calenminder/blob/main/PRIVACY.md")!
    static let privacyStatement = "All data stays on your device - no servers, no analytics."

    let versionLabel: String
    let privacyStatement: String
    let githubURL: URL
    let privacyPolicyURL: URL

    init(
        shortVersion: String?,
        buildNumber: String?,
        githubURL: URL = AppAboutInfo.githubURL,
        privacyPolicyURL: URL = AppAboutInfo.privacyPolicyURL,
        privacyStatement: String = AppAboutInfo.privacyStatement
    ) {
        let version = (shortVersion?.isEmpty == false) ? shortVersion! : "unknown"
        let build = (buildNumber?.isEmpty == false) ? buildNumber! : "unknown"
        self.versionLabel = "Version \(version) (\(build))"
        self.privacyStatement = privacyStatement
        self.githubURL = githubURL
        self.privacyPolicyURL = privacyPolicyURL
    }

    /// Reads `CFBundleShortVersionString`/`CFBundleVersion` from `bundle`'s
    /// info dictionary. Production call site passes `.main` (the app's own
    /// bundle at runtime); tests pass a `Bundle` built from an arbitrary
    /// dictionary (or omit this factory and construct `AppAboutInfo`
    /// directly) so version-formatting logic is exercised without depending
    /// on the compiled app bundle.
    static func fromBundle(_ bundle: Bundle) -> AppAboutInfo {
        AppAboutInfo(
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}

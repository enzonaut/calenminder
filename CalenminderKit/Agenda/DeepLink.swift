import Foundation

/// A parsed `calenminder://` URL. Deep links are untrusted, externally
/// triggerable input (widget taps from Phase 5, Spotlight, Shortcuts, a
/// malicious/buggy third party constructing the scheme by hand) - `parse`
/// never throws and never force-unwraps anything derived from `url`; a
/// malformed URL simply produces `nil`, which callers must route to a
/// not-found state rather than ignoring (see `DeepLinkRouter`).
///
/// Lives in `CalenminderKit/Agenda/` (not the app target) because Phase 5's
/// widget will build these same URLs for its row/task deep links and should
/// share this exact parsing/building logic rather than re-deriving it.
public enum DeepLink: Equatable, Sendable {
    case event(externalIdentifier: String, occurrenceDate: Date)
    case task(externalIdentifier: String)

    public static let scheme = "calenminder"

    /// `nil` for anything that is not a well-formed `calenminder://event` or
    /// `calenminder://task` link: wrong/missing scheme, unknown host, or a
    /// missing/empty/unparseable required parameter.
    public static func parse(_ url: URL) -> DeepLink? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == scheme
        else { return nil }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let raw = items.first(where: { $0.name == name })?.value else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        switch components.host?.lowercased() {
        case "event":
            guard
                let id = value("id"),
                let occurrenceRaw = value("occurrence"),
                let epoch = TimeInterval(occurrenceRaw),
                epoch.isFinite
            else { return nil }
            return .event(externalIdentifier: id, occurrenceDate: Date(timeIntervalSince1970: epoch))
        case "task":
            guard let id = value("id") else { return nil }
            return .task(externalIdentifier: id)
        default:
            return nil
        }
    }

    /// The URL this link round-trips through `parse(_:)` as. Used by the app
    /// itself (and, from Phase 5, the widget) to construct links - never
    /// fails, since every component is a fixed literal or a plain string
    /// `URLComponents` percent-encodes automatically.
    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .event(let id, let occurrenceDate):
            components.host = "event"
            components.queryItems = [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "occurrence", value: String(occurrenceDate.timeIntervalSince1970)),
            ]
        case .task(let id):
            components.host = "task"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
        }
        // Fixed scheme/host plus percent-encoded query items always produce a
        // valid URL; the fallback exists only so this is total, never `!`.
        return components.url ?? URL(string: "calenminder://invalid")!
    }
}

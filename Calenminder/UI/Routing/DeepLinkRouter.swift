import Foundation
import CalenminderKit

/// Turns an incoming `calenminder://` URL into a navigation route. Deep
/// links are untrusted, externally triggerable input: a URL that does not
/// parse as a `DeepLink` (wrong scheme, missing/garbled parameters) routes
/// to `.notFound` rather than being silently dropped - `onOpenURL` only ever
/// calls in for URLs matching this app's registered scheme, so anything
/// that reaches here was meant for us and deserves a visible response, never
/// a crash and never silence (DW-4.4).
@MainActor
final class DeepLinkRouter: ObservableObject {
    enum Route: Equatable {
        case eventDetail(externalIdentifier: String, occurrenceDate: Date)
        case taskDetail(externalIdentifier: String)
        case notFound
    }

    @Published var route: Route?

    func handle(url: URL) {
        guard let link = DeepLink.parse(url) else {
            route = .notFound
            return
        }
        switch link {
        case .event(let id, let occurrenceDate):
            route = .eventDetail(externalIdentifier: id, occurrenceDate: occurrenceDate)
        case .task(let id):
            route = .taskDetail(externalIdentifier: id)
        }
    }

    func dismiss() {
        route = nil
    }
}

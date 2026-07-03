import Testing
import Foundation
@testable import Calenminder

@MainActor
struct DeepLinkRouterTests {
    @Test("A well-formed event URL routes to .eventDetail")
    func wellFormedEventURLRoutesToEventDetail() {
        let router = DeepLinkRouter()
        let url = URL(string: "calenminder://event?id=abc&occurrence=1000")!

        router.handle(url: url)

        #expect(router.route == .eventDetail(externalIdentifier: "abc", occurrenceDate: Date(timeIntervalSince1970: 1000)))
    }

    @Test("A well-formed task URL routes to .taskDetail")
    func wellFormedTaskURLRoutesToTaskDetail() {
        let router = DeepLinkRouter()
        let url = URL(string: "calenminder://task?id=xyz")!

        router.handle(url: url)

        #expect(router.route == .taskDetail(externalIdentifier: "xyz"))
    }

    @Test("DW-4.4: a malformed URL routes to .notFound rather than crashing or being ignored")
    func test_DW_4_4_malformedURLRoutesToNotFound() {
        let router = DeepLinkRouter()
        let url = URL(string: "calenminder://event?id=abc")! // missing occurrence

        router.handle(url: url)

        #expect(router.route == .notFound)
    }

    @Test("DW-4.4: a URL with an unrecognized host routes to .notFound")
    func unrecognizedHostRoutesToNotFound() {
        let router = DeepLinkRouter()
        let url = URL(string: "calenminder://something-else")!

        router.handle(url: url)

        #expect(router.route == .notFound)
    }

    @Test("dismiss() clears the route")
    func dismissClearsRoute() {
        let router = DeepLinkRouter()
        router.handle(url: URL(string: "calenminder://task?id=x")!)
        router.dismiss()
        #expect(router.route == nil)
    }
}

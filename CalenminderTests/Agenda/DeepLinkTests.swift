import Testing
import Foundation
@testable import CalenminderKit

/// DW-4.4: malformed deep links must fail to parse (never crash, never
/// silently resolve to something wrong) so the caller can route to a
/// not-found state.
struct DeepLinkTests {
    @Test("A well-formed event link parses")
    func wellFormedEventLinkParses() {
        let url = URL(string: "calenminder://event?id=abc123&occurrence=1000")!
        #expect(DeepLink.parse(url) == .event(externalIdentifier: "abc123", occurrenceDate: Date(timeIntervalSince1970: 1000)))
    }

    @Test("A well-formed task link parses")
    func wellFormedTaskLinkParses() {
        let url = URL(string: "calenminder://task?id=xyz")!
        #expect(DeepLink.parse(url) == .task(externalIdentifier: "xyz"))
    }

    @Test("DW-4.4: a URL with the wrong scheme fails to parse")
    func wrongSchemeFailsToParse() {
        let url = URL(string: "https://event?id=abc&occurrence=1000")!
        #expect(DeepLink.parse(url) == nil)
    }

    @Test("DW-4.4: a URL with an unknown host fails to parse")
    func unknownHostFailsToParse() {
        let url = URL(string: "calenminder://unknown?id=abc")!
        #expect(DeepLink.parse(url) == nil)
    }

    @Test("DW-4.4: an event link missing the occurrence parameter fails to parse")
    func eventLinkMissingOccurrenceFailsToParse() {
        let url = URL(string: "calenminder://event?id=abc")!
        #expect(DeepLink.parse(url) == nil)
    }

    @Test("DW-4.4: an event link with a non-numeric occurrence fails to parse")
    func eventLinkWithNonNumericOccurrenceFailsToParse() {
        let url = URL(string: "calenminder://event?id=abc&occurrence=not-a-number")!
        #expect(DeepLink.parse(url) == nil)
    }

    @Test("DW-4.4: a link with an empty id fails to parse")
    func linkWithEmptyIdFailsToParse() {
        let url = URL(string: "calenminder://task?id=")!
        #expect(DeepLink.parse(url) == nil)
    }

    @Test("DW-4.4: a link with a whitespace-only id fails to parse")
    func linkWithWhitespaceOnlyIdFailsToParse() {
        let url = URL(string: "calenminder://task?id=%20%20")!
        #expect(DeepLink.parse(url) == nil)
    }

    @Test("DW-4.4: a link with no query items at all fails to parse")
    func linkWithNoQueryItemsFailsToParse() {
        let url = URL(string: "calenminder://task")!
        #expect(DeepLink.parse(url) == nil)
    }

    @Test("An event link's built URL round-trips through parse")
    func eventLinkRoundTrips() {
        let link = DeepLink.event(externalIdentifier: "abc 123", occurrenceDate: Date(timeIntervalSince1970: 54321))
        #expect(DeepLink.parse(link.url) == link)
    }

    @Test("A task link's built URL round-trips through parse")
    func taskLinkRoundTrips() {
        let link = DeepLink.task(externalIdentifier: "id-with-special-chars-&=?")
        #expect(DeepLink.parse(link.url) == link)
    }
}

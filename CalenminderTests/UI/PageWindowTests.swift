import Testing
@testable import Calenminder

/// DW-F5.2/DW-F5.3/DW-F5.4: the pure 3-tag sliding-window math shared by
/// every swipeable calendar screen (Week strip/Month/Year - Day view uses a
/// `DragGesture` instead, see `AgendaView`'s doc comment).
struct PageWindowTests {
    @Test("Settling on the previous tag (0) reports direction -1")
    func settlingOnPreviousTagReportsNegativeOne() {
        #expect(PageWindow.direction(forSelection: 0) == -1)
    }

    @Test("Settling on the center tag (1) reports direction 0 - nothing to do")
    func settlingOnCenterTagReportsZero() {
        #expect(PageWindow.direction(forSelection: PageWindow.centerIndex) == 0)
    }

    @Test("Settling on the next tag (2) reports direction +1")
    func settlingOnNextTagReportsPositiveOne() {
        #expect(PageWindow.direction(forSelection: 2) == 1)
    }

    @Test("Any tag below center reports -1, any tag above center reports +1 - a total comparison, not an enumerated switch")
    func totalComparisonBeyondTheThreeKnownTags() {
        #expect(PageWindow.direction(forSelection: -5) == -1)
        #expect(PageWindow.direction(forSelection: 99) == 1)
    }

    @Test("centerIndex is 1 - the middle of the three tags")
    func centerIndexIsOne() {
        #expect(PageWindow.centerIndex == 1)
    }
}

import Foundation

/// Shared 3-tag sliding-window math behind every swipeable calendar screen
/// (Week strip, Month, Year - Day view uses a `DragGesture` instead, see
/// `AgendaView`'s own doc comment). Every paged screen uses the identical
/// recipe: a `TabView(selection:)` with exactly three tags - 0 = previous
/// period, 1 = `centerIndex` (the real, externally-owned view model; every
/// settle starts and ends here), 2 = next period. `direction(forSelection:)`
/// turns wherever the selection settled into -1/0/+1 so the caller can invoke
/// the *same* "go to previous/next period" method a chevron button already
/// calls, then recenter the window - keeping swipe and chevron perpetually in
/// sync by construction rather than as two paths that could drift apart. See
/// the Feature 5 discovery doc's "Shared primitive: PageWindow" section.
enum PageWindow {
    static let centerIndex = 1

    /// -1 if `selection` settled on the previous page, +1 on the next page,
    /// 0 if it is still centered (mid-swipe, or a programmatic reset).
    ///
    /// A total comparison against `centerIndex`, not a switch over the three
    /// known tags: it stays correct (and never traps) even if some future
    /// change altered the page count, rather than needing every such change
    /// to also update an enumerated switch here.
    static func direction(forSelection selection: Int) -> Int {
        if selection < centerIndex { return -1 }
        if selection > centerIndex { return 1 }
        return 0
    }
}

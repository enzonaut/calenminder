import XCTest

/// Simulator-only regression coverage for two real layout defects found and
/// fixed in the Feature 4 UI bug-fix pass (see
/// `.code-foundations/build/2026-07-03-calenminder-ui-fix-discovery.md`):
///
/// 1. Day view's `ToolbarItemGroup(.navigationBarLeading)` used to carry
///    enough controls (back + previous-day + "Today" + next-day) that the
///    principal `CalendarModeSwitcher` had no room and simply did not render
///    - confirmed both visually and via the accessibility tree, on both a
///    regular-width and a compact-width simulator. Neither Swift Testing's
///    `ImageRenderer`-based view-smoke tests (`ViewSmokeTests.swift`) nor any
///    unit test can catch a *real* nav-bar layout collapse like this - only
///    driving the actual rendered toolbar (this file) can.
/// 2. `MonthView`'s day grid used a `LazyVGrid` directly inside a
///    non-scrolling `VStack`, which silently rendered only the first week and
///    left the rest of the month blank.
///
/// Requires Calendars/Reminders full access already granted to
/// `com.enzonaut.calenminder` on the destination simulator (see
/// `make test-integration`'s header comment in the Makefile - this suite
/// runs alongside those EventKit integration suites for the same reason:
/// simulator-only, needs a real permission grant, excluded from the default
/// `make test`).
final class CalendarToolbarLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// DW-F4.2: the mode switcher must actually render in Day view, and none
    /// of Day view's toolbar controls may overlap one another. `XCUIElement
    /// .frame` reflects real, on-screen layout (not an offscreen
    /// `ImageRenderer` guess), so this is a direct, precise check - not an
    /// approximation.
    func test_DW_F4_2_dayViewToolbarControlsDoNotOverlap() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 10))

        let switcher = app.segmentedControls["calendar-mode-switcher"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), "calendar-mode-switcher must render in Day view")
        XCTAssertTrue(switcher.isHittable, "calendar-mode-switcher must be hittable, not just present")

        let today = app.buttons["agenda-today"]
        let calendarSettings = app.buttons["agenda-calendar-settings"]
        let addMenu = app.buttons["agenda-add-menu"]
        for control in [today, calendarSettings, addMenu] {
            XCTAssertTrue(control.exists, "\(control) should exist in Day view's toolbar")
            XCTAssertTrue(control.isHittable, "\(control) should be hittable")
        }

        let frames = ["Today": today.frame, "switcher": switcher.frame, "settings": calendarSettings.frame, "add": addMenu.frame]
        let names = Array(frames.keys)
        for i in 0..<names.count {
            for j in (i + 1)..<names.count {
                let a = frames[names[i]]!
                let b = frames[names[j]]!
                XCTAssertFalse(a.intersects(b), "\(names[i]) \(a) overlaps \(names[j]) \(b)")
            }
        }
    }

    // MARK: - DW-B2.2: toolbar overlap across every reachable nav-bar state

    /// DW-B2.2a: Month view's leading `ToolbarItemGroup` can carry three
    /// chevrons at once (back + previous-month + next-month, when Month was
    /// reached by drilling down from Year), alongside the principal
    /// `CalendarModeSwitcher`. The switcher used `.fixedSize()`, so it refused
    /// to compress and its centered frame could slide underneath the leading
    /// chevrons - a real overlap the launch-only `test_DW_F4_2` never exercised
    /// (that path has no back button). Drill Year -> Month so all three leading
    /// chevrons are present, then assert no two nav-bar controls intersect.
    func test_DW_B2_2_monthViewToolbarControlsDoNotOverlap() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 10))

        // Year -> tap the current month tile -> Month view WITH a back button.
        app.segmentedControls["calendar-mode-switcher"].buttons["Year"].tap()
        XCTAssertTrue(app.otherElements["root-year"].waitForExistence(timeout: 5))

        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let monthTile = app.descendants(matching: .any).matching(identifier: "year-month-\(year)-\(month)").firstMatch
        XCTAssertTrue(monthTile.waitForExistence(timeout: 5))
        monthTile.tap()
        XCTAssertTrue(app.otherElements["root-month"].waitForExistence(timeout: 5))

        let back = app.buttons["month-back"]
        let previous = app.buttons["month-previous"]
        let next = app.buttons["month-next"]
        let switcher = app.segmentedControls["calendar-mode-switcher"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "month-back must be present after drilling down from Year")
        for control in [back, previous, next] {
            XCTAssertTrue(control.isHittable, "\(control) should be hittable in the drilled-down Month toolbar")
        }
        XCTAssertTrue(switcher.isHittable, "the mode switcher must remain hittable in Month view")
        attachOverlapScreenshot(app, name: "month-toolbar-overlap-\(deviceTag(app))")

        assertNoOverlap(
            ["back": back.frame, "previous": previous.frame, "next": next.frame, "switcher": switcher.frame]
        )
    }

    /// DW-B2.2b: Year view's leading group carries two chevrons
    /// (previous-year + next-year) alongside the principal switcher. Year is
    /// always the top mode (never has a back button), but the `.fixedSize()`
    /// switcher can still slide under the two chevrons on a narrow width.
    func test_DW_B2_2_yearViewToolbarControlsDoNotOverlap() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 10))

        app.segmentedControls["calendar-mode-switcher"].buttons["Year"].tap()
        XCTAssertTrue(app.otherElements["root-year"].waitForExistence(timeout: 5))

        let previous = app.buttons["year-previous"]
        let next = app.buttons["year-next"]
        let switcher = app.segmentedControls["calendar-mode-switcher"]
        for control in [previous, next] {
            XCTAssertTrue(control.waitForExistence(timeout: 5), "\(control) should exist in Year view's toolbar")
            XCTAssertTrue(control.isHittable, "\(control) should be hittable in Year view")
        }
        XCTAssertTrue(switcher.isHittable, "the mode switcher must remain hittable in Year view")
        attachOverlapScreenshot(app, name: "year-toolbar-overlap-\(deviceTag(app))")

        assertNoOverlap(["previous": previous.frame, "next": next.frame, "switcher": switcher.frame])
    }

    /// DW-B2.2c: the specific gap called out in the Feature 4 doc -
    /// `test_DW_F4_2` only checks Day view AT LAUNCH (no back button). After
    /// drilling Month -> Day, the leading group additionally carries the
    /// "agenda-back" button next to "Today", tightening the space the
    /// principal switcher and the two trailing buttons must share. Drill down,
    /// then assert none of the five nav-bar controls overlap.
    func test_DW_B2_2_dayViewAfterDrilldownToolbarControlsDoNotOverlap() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 10))

        // Day (launch) -> Month (direct switch, no back) -> tap a day -> Day
        // WITH a back button (selectDay remembers Month as the parent).
        app.segmentedControls["calendar-mode-switcher"].buttons["Month"].tap()
        XCTAssertTrue(app.otherElements["root-month"].waitForExistence(timeout: 5))

        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        let dayCell = app.descendants(matching: .any).matching(identifier: "month-day-\(year)-\(month)-\(day)").firstMatch
        XCTAssertTrue(dayCell.waitForExistence(timeout: 5))
        dayCell.tap()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 5))

        let back = app.buttons["agenda-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "agenda-back must be present after drilling Month -> Day")
        let today = app.buttons["agenda-today"]
        let switcher = app.segmentedControls["calendar-mode-switcher"]
        let calendarSettings = app.buttons["agenda-calendar-settings"]
        let addMenu = app.buttons["agenda-add-menu"]
        for control in [back, today, calendarSettings, addMenu] {
            XCTAssertTrue(control.isHittable, "\(control) should be hittable in the drilled-down Day toolbar")
        }
        XCTAssertTrue(switcher.isHittable, "the mode switcher must remain hittable in the drilled-down Day view")
        attachOverlapScreenshot(app, name: "day-drilldown-toolbar-overlap-\(deviceTag(app))")

        assertNoOverlap([
            "back": back.frame, "Today": today.frame, "switcher": switcher.frame,
            "settings": calendarSettings.frame, "add": addMenu.frame,
        ])
    }

    // MARK: - DW-B2.2 helpers

    /// Asserts every pair of the named nav-bar control frames is disjoint -
    /// the same frame-intersection technique `test_DW_F4_2` uses, factored out
    /// so all three DW-B2.2 cases apply it identically. `XCUIElement.frame`
    /// reflects real on-screen layout, so an intersection is a real, visible
    /// overlap, not an approximation.
    private func assertNoOverlap(_ frames: [String: CGRect], file: StaticString = #filePath, line: UInt = #line) {
        let names = Array(frames.keys)
        for i in 0..<names.count {
            for j in (i + 1)..<names.count {
                let a = frames[names[i]]!
                let b = frames[names[j]]!
                XCTAssertFalse(a.intersects(b), "\(names[i]) \(a) overlaps \(names[j]) \(b)", file: file, line: line)
            }
        }
    }

    /// A short device tag ("regular"/"compact") derived from the running
    /// simulator's screen width, so the before/after evidence PNGs from the
    /// regular-width and the narrow (iPhone SE) runs land under distinct names
    /// instead of overwriting each other.
    private func deviceTag(_ app: XCUIApplication) -> String {
        app.windows.element(boundBy: 0).frame.width < 390 ? "compact" : "regular"
    }

    /// Writes a real PNG to `.code-foundations/build/bugfix-evidence/` (not
    /// just an `.xcresult` attachment), mirroring `SwipeNavigationUITests
    /// .attachScreenshot`, so the DW-B2.2 before/after overlap evidence lands
    /// where the bug-fix report references it.
    private func attachOverlapScreenshot(_ app: XCUIApplication, name: String) {
        let evidenceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".code-foundations/build/bugfix-evidence")
        try? FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: evidenceDirectory.appendingPathComponent("\(name).png"))
    }

    /// DW-F4.3: every day of the currently-displayed month must be visible
    /// and tappable, not just the first week. The last calendar day of the
    /// month is (for any month with more than 7 days, i.e. always) in a row
    /// after the first - so this is a timeless, month-agnostic guard against
    /// the grid collapsing back to "week 1 only".
    func test_DW_F4_3_monthViewShowsEveryDayOfTheMonth() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 10))
        app.segmentedControls["calendar-mode-switcher"].buttons["Month"].tap()
        XCTAssertTrue(app.otherElements["root-month"].waitForExistence(timeout: 5))

        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        guard let range = calendar.range(of: .day, in: .month, for: now) else {
            XCTFail("could not compute days in current month")
            return
        }
        let lastDay = range.count

        // `.otherElements`/`.staticTexts` alone are not reliable here: a day
        // cell's accessibility identifier surfaces on whichever child
        // SwiftUI happens to expose (the day-number `Text`, or - when that
        // day also has an event dot - the dot's container instead). Query by
        // identifier across any element type so this doesn't depend on
        // whether a given day happens to have an event.
        func dayCell(_ day: Int) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "month-day-\(year)-\(month)-\(day)").firstMatch
        }

        let firstDayCell = dayCell(1)
        XCTAssertTrue(firstDayCell.waitForExistence(timeout: 5))
        XCTAssertTrue(firstDayCell.isHittable, "first day of the month should be visible")

        let lastDayCell = dayCell(lastDay)
        XCTAssertTrue(lastDayCell.waitForExistence(timeout: 5), "last day of the month (\(lastDay)) must exist in the grid")
        XCTAssertTrue(lastDayCell.isHittable, "last day of the month (\(lastDay)) must be visible/tappable, not collapsed off-screen")
    }
}

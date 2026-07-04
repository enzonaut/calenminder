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

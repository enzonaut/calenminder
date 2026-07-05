import XCTest

/// Bug 2 (recurrence day) regression, driven end-to-end exactly as the user
/// hit it: "i created a task for every monday, and i see it today sunday". A
/// weekly-recurring task must first appear on its own weekday, never on the
/// day it happened to be composed.
///
/// The date can't be controlled on the simulator, so the scenario is expressed
/// date-relative: compose a weekly task for *tomorrow's* weekday (guaranteed
/// not today's), then prove the task is absent from today's agenda and present
/// on tomorrow's - the same "wrong day / right day" split the user reported,
/// independent of what today actually is.
///
/// Requires Calendars/Reminders full access already granted to
/// `com.enzonaut.calenminder` on the destination simulator, same as
/// `SwipeNavigationUITests` (see that file's header comment and the Makefile's
/// `test-integration` target, which this suite also joins).
final class RecurringTaskDueDayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_DW_B2_1_weeklyTaskAppearsOnItsWeekdayNotTheComposedDay() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 10))

        // Tomorrow's weekday is always different from today's, so a weekly task
        // for it must NOT be due today and MUST be due tomorrow - and, because
        // its next occurrence is exactly tomorrow (delta 1), it is a future
        // anchor, so the overdue-rollover path can never surface it today either.
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) else {
            XCTFail("could not compute tomorrow")
            return
        }
        let targetWeekday = calendar.component(.weekday, from: tomorrow)
        let weekdayName = calendar.weekdaySymbols[targetWeekday - 1]

        let title = uniqueTitle("Weekly \(weekdayName) Task")
        seedWeeklyTask(app, title: title, weekdayName: weekdayName)

        let list = app.descendants(matching: .any).matching(identifier: "agenda-list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let todayTitle = currentTitle(app)

        // The bug itself: the task must NOT be on today's agenda. Sweep the
        // whole list first - a genuinely absent task never enters the tree, so
        // if scrolling never reveals its row, it is truly not due today.
        let circleToday = circleButton(forRowTitled: title, in: app)
        for _ in 0..<8 where !circleToday.exists { list.swipeUp() }
        attachScreenshot(app, name: "recurrence-today-should-be-absent")
        XCTAssertFalse(circleToday.exists, "a weekly '\(weekdayName)' task must not appear on today (\(todayTitle))")

        // Page to tomorrow (its weekday) - the same horizontal day-swipe the
        // agenda already supports - and prove the task is there.
        list.swipeLeft()
        let tomorrowTitle = currentTitle(app)
        XCTAssertNotEqual(todayTitle, tomorrowTitle, "swiping left should page to tomorrow")

        let circleTomorrow = circleButton(forRowTitled: title, in: app)
        for _ in 0..<8 where !circleTomorrow.exists { list.swipeUp() }
        attachScreenshot(app, name: "recurrence-tomorrow-should-be-present")
        XCTAssertTrue(circleTomorrow.waitForExistence(timeout: 5), "a weekly '\(weekdayName)' task must appear on its weekday (\(tomorrowTitle))")

        // Triangulate: on the day after its weekday the still-incomplete task
        // is allowed to appear - but only as the app's designed overdue
        // rollover (it was due yesterday and never completed), never as a
        // due-that-day item. The "Overdue" marker inside its own row is what
        // distinguishes the two: a wrongly-anchored or wrongly-expanded task
        // would render there as plainly due (no marker) - exactly the state
        // the pre-fix Sunday screenshot showed.
        list.swipeLeft()
        let dayAfterTitle = currentTitle(app)
        XCTAssertNotEqual(tomorrowTitle, dayAfterTitle, "swiping left again should page to the day after tomorrow")
        let circleDayAfter = circleButton(forRowTitled: title, in: app)
        for _ in 0..<8 where !circleDayAfter.exists { list.swipeUp() }
        if circleDayAfter.exists {
            let row = app.cells.containing(NSPredicate(format: "label == %@", title)).firstMatch
            let overdueMarker = row.staticTexts["Overdue"]
            XCTAssertTrue(
                overdueMarker.exists,
                "on \(dayAfterTitle) the weekly task may only appear as overdue rollover (with the Overdue marker), never as due that day"
            )
        }
    }

    // MARK: - Helpers (mirrors SwipeNavigationUITests' hardened patterns:
    //         run-unique titles, cell-scoped queries, hittable-waits)

    private func currentTitle(_ app: XCUIApplication) -> String {
        app.navigationBars.element(boundBy: 0).identifier
    }

    private func uniqueTitle(_ base: String) -> String {
        "\(base) \(UUID().uuidString.prefix(8))"
    }

    /// Seeds a weekly-recurring task through the real composer: title, the
    /// "Repeats weekly" toggle, and the weekday picker set to `weekdayName`.
    private func seedWeeklyTask(_ app: XCUIApplication, title: String, weekdayName: String) {
        tapWhenReady(app.buttons["agenda-add-menu"])
        let newTask = app.buttons["New Task"]
        XCTAssertTrue(newTask.waitForExistence(timeout: 5), "the add menu's New Task item should appear")
        tapWhenReady(newTask)

        let titleField = app.textFields["task-composer-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        tapWhenReady(titleField)
        titleField.typeText(title)

        // Dismiss the keyboard before touching rows below the title field -
        // with the keyboard up, the toggle row can sit underneath it, and a
        // synthesized tap then lands on the keyboard instead of the row
        // (observed empirically: the tap "succeeded" but the toggle never
        // flipped, so the weekday picker row never appeared).
        if app.keyboards.count > 0 {
            let returnKey = app.keyboards.buttons["Return"]
            if returnKey.exists { returnKey.tap() } else { app.swipeDown() }
        }

        // The switch element's frame spans the whole Form row, and `.tap()`
        // taps its center - the *label* area, which does not flip a SwiftUI
        // `Toggle` (only the trailing knob does; confirmed empirically: a
        // center tap left the toggle off every time). Tap near the trailing
        // edge by coordinate instead, and treat the weekday picker row
        // appearing (it only renders while `repeatsWeekly` is on) as the
        // authoritative "the toggle really flipped" signal, retrying once.
        let weeklyToggle = app.switches["task-composer-repeats"].firstMatch
        XCTAssertTrue(weeklyToggle.waitForExistence(timeout: 5))
        let weekdayRow = app.descendants(matching: .any).matching(identifier: "task-composer-weekday").firstMatch
        for _ in 0..<2 where !weekdayRow.exists {
            weeklyToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            _ = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: weekdayRow)], timeout: 3)
        }
        XCTAssertTrue(weekdayRow.exists, "the 'Repeats weekly' toggle should turn on and reveal the weekday picker row")

        // The weekday `Picker` row is not reliably exposed as a `.buttons`
        // element - its accessibility identifier surfaces on whichever child
        // SwiftUI happens to pick (the exact identifier-flattening quirk
        // `SwipeNavigationUITests`/`MonthDayCell` document), so query it by
        // identifier across ANY element type. Tapping the row opens the menu
        // of weekday options; tapping the weekday name selects it. Selection
        // is only trusted once the collapsed row itself reads back the chosen
        // weekday (menu pickers surface the selection in their label/value) -
        // a tap synthesized while the menu is still animating in can be
        // swallowed, silently leaving the default (today's own weekday), which
        // would make this test pass or fail for the wrong reason entirely.
        let picker = app.descendants(matching: .any).matching(identifier: "task-composer-weekday").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the weekday picker row should exist once 'Repeats weekly' is on")
        let selectionTaken = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", weekdayName, weekdayName)
        for _ in 0..<3 where !selectionTaken.evaluate(with: picker) {
            tapWhenReady(picker)
            let weekdayOption = app.buttons[weekdayName].firstMatch
            if weekdayOption.waitForExistence(timeout: 3) {
                waitForSteadyFrame(of: weekdayOption)
                weekdayOption.tap()
            }
            _ = XCTWaiter().wait(for: [expectation(for: selectionTaken, evaluatedWith: picker)], timeout: 3)
        }
        XCTAssertTrue(
            selectionTaken.evaluate(with: picker),
            "the weekday picker row should read back '\(weekdayName)' before saving (actual label: '\(picker.label)', value: '\(String(describing: picker.value))')"
        )

        tapWhenReady(app.buttons["task-composer-save"])
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 5))
    }

    /// Waits until `element`'s frame reports the same value on two consecutive
    /// samples and the element is hittable - i.e. any in-flight presentation/
    /// menu animation around it has settled. Same helper (and rationale) as
    /// `SwipeNavigationUITests.waitForSteadyFrame(of:)`: a tap synthesized
    /// mid-animation can be silently swallowed. Best-effort: on timeout it
    /// returns and the subsequent tap behaves as it would have anyway.
    private func waitForSteadyFrame(of element: XCUIElement, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = element.exists ? element.frame : .null
        while Date() < deadline {
            usleep(300_000)
            let current = element.exists ? element.frame : .null
            if current == previous, !current.isEmpty, !current.isNull, element.isHittable { return }
            previous = current
        }
    }

    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(element) should exist before tapping")
        if !element.isHittable {
            let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
            _ = XCTWaiter().wait(for: [hittable], timeout: timeout)
        }
        element.tap()
    }

    /// The incomplete-task checkmark `Button` for the row whose title is
    /// exactly `title`, scoped to that one `List` row (never "whichever circle
    /// is first") - identical scoping to `SwipeNavigationUITests`, and for the
    /// same reason: every incomplete task's checkmark shares the label "circle",
    /// and the simulator's real Reminders store carries pre-existing rows.
    private func circleButton(forRowTitled title: String, in app: XCUIApplication) -> XCUIElement {
        let row = app.cells.containing(NSPredicate(format: "label == %@", title)).firstMatch
        return row.buttons.matching(NSPredicate(format: "label == 'circle'")).firstMatch
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let evidenceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".code-foundations/build/bugfix-evidence")
        try? FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: evidenceDirectory.appendingPathComponent("\(name).png"))
    }
}

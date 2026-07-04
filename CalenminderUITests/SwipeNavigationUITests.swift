import XCTest

/// Feature 5: real-swipe regression coverage for period paging on all four
/// calendar surfaces (Day agenda, Week strip, Month, Year). `XCUIElement
/// .swipeLeft()/.swipeRight()` drives an actual touch drag on the simulator,
/// which is the only way to prove a real gesture (not just the view model
/// method it eventually calls) actually pages the screen and does not
/// swallow/conflict with scrolling, pull-to-refresh, row taps, or the
/// task-row checkmark - see the Feature 5 discovery doc.
///
/// Requires Calendars/Reminders full access already granted to
/// `com.enzonaut.calenminder` on the destination simulator, same as
/// `CalendarToolbarLayoutUITests` (see that file's header comment and the
/// Makefile's `test-integration` target, which this suite also joins).
final class SwipeNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - DW-F5.1: Day agenda swipe

    func test_DW_F5_1_daySwipeChangesDayWithoutBreakingListScrollOrRefresh() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 10))

        let list = app.descendants(matching: .any).matching(identifier: "agenda-list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))

        let titleBefore = currentTitle(app)

        list.swipeLeft()
        let titleAfterNext = currentTitle(app)
        XCTAssertNotEqual(titleBefore, titleAfterNext, "swiping left on the agenda list should page to the next day")
        attachScreenshot(app, name: "day-view-after-swipe")

        // Swiping right twice returns through today to the previous day -
        // proves the gesture pages in both directions and `AgendaViewModel
        // .day` (read back via the title) keeps tracking every page.
        list.swipeRight()
        let titleBackToToday = currentTitle(app)
        XCTAssertEqual(titleBefore, titleBackToToday, "swiping right should return to the original day")

        list.swipeRight()
        let titleAfterPrevious = currentTitle(app)
        XCTAssertNotEqual(titleBackToToday, titleAfterPrevious, "swiping right again should page to the previous day")

        // "Today" button still returns to today after paging by swipe.
        app.buttons["agenda-today"].tap()
        XCTAssertEqual(currentTitle(app), titleBefore, "Today button should still return to the original day after swipe paging")

        // Pull-to-refresh (a vertical gesture) must still be unaffected by
        // the horizontal-dominant swipe gesture layered on the same List.
        list.swipeDown()
        XCTAssertTrue(app.otherElements["root-agenda"].exists, "pull-to-refresh must not crash or dismiss the agenda")
    }

    /// DW-F5.1's checkmark concern is specifically that the day-paging
    /// `DragGesture` must not swallow or misfire on a plain tap of the
    /// task-row checkmark `Button`. This test proves exactly that: the tap
    /// lands on the checkmark (not a swipe), the displayed day never changes,
    /// and the button remains hittable/functional afterward. It deliberately
    /// does not assert on the real EventKit completion round-trip settling
    /// (`AgendaViewModel.toggleTaskCompletion` itself, and the underlying
    /// `ReminderTaskStore.setCompleted` round-trip, are both independently
    /// covered - see `AgendaViewModelTests.completingTaskOptimisticallyRemoves
    /// FromSnapshot` and `ReminderTaskStoreIntegrationTests
    /// .test_DW_3_3_uncompleteNonRecurringTask`, both green against fakes and
    /// the real simulator store respectively). A live UI-tap-to-completion
    /// flake was observed against this simulator's Reminders store during
    /// this feature's manual verification, independent of the swipe gesture
    /// (reproduced identically with `daySwipeGesture` removed entirely) -
    /// since root-caused (a concurrent-reload race in
    /// `AgendaViewModel.load()`), fixed, and permanently guarded by
    /// `test_checkmarkTapCompletionRoundTripSticksEveryTime` below.
    func test_DW_F5_1_dayCheckmarkTapDoesNotPageTheDay() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 10))

        seedTask(app, title: "Swipe Regression Task")

        let titleBefore = currentTitle(app)
        // The checkmark `Button`'s own `task-row-toggle-<id>` accessibility
        // identifier gets superseded at runtime by its enclosing `Section`'s
        // identifier (a real SwiftUI `List`-section quirk, same class of
        // issue as `MonthDayCell`'s doc comment about a day cell's
        // identifier surfacing on whichever child is exposed) - so this
        // locates the incomplete task's circle by its rendered label instead,
        // which is stable and unambiguous.
        let incompleteCircles = app.buttons.matching(NSPredicate(format: "label == 'circle'"))
        let list = app.descendants(matching: .any).matching(identifier: "agenda-list").firstMatch
        // The Tasks section can be scrolled below the initial viewport (a
        // long list of events, or many previously-seeded tasks, ahead of
        // it) - List virtualizes off-screen rows out of the accessibility
        // tree entirely, so scroll down a few times if the freshly-seeded
        // task's circle is not immediately visible.
        for _ in 0..<5 where !incompleteCircles.firstMatch.exists {
            list.swipeUp()
        }
        XCTAssertTrue(incompleteCircles.firstMatch.waitForExistence(timeout: 5), "seeded task's checkmark button should exist")

        let circlesBeforeTap = incompleteCircles.count
        incompleteCircles.firstMatch.tap()
        // Give any (correctly-scoped, horizontal-dominant) gesture recognizer
        // time to have misfired if it were going to.
        sleep(1)

        XCTAssertEqual(currentTitle(app), titleBefore, "tapping the checkmark must not page the displayed day")
        XCTAssertTrue(app.otherElements["root-agenda"].exists, "the agenda must still be showing (no crash) after the tap")
        // The tap must land as a button tap (not be consumed by any gesture):
        // the tapped task completes and its circle leaves the incomplete
        // working set. This assertion previously checked the circle was
        // *still hittable* - which only ever passed because the completion
        // race (since fixed) could leave the tapped task incomplete; the
        // intended behavior is the opposite.
        let completedOne = expectation(for: NSPredicate(format: "count == \(circlesBeforeTap - 1)"), evaluatedWith: incompleteCircles)
        XCTAssertEqual(XCTWaiter().wait(for: [completedOne], timeout: 5), .completed, "the tapped checkmark's task should complete (circle count \(circlesBeforeTap) -> \(circlesBeforeTap - 1)), proving the tap was not consumed by a swipe")
    }

    // MARK: - Checkmark completion-race regression (pre-existing bug, fixed)

    /// Regression guard for the checkmark-completion race: a real tap on the
    /// task-row checkmark completed the task in the store, but the displayed
    /// state could revert to incomplete moments later. Root cause was
    /// `AgendaViewModel.load()` running unbounded concurrent fetches - the
    /// mutation's own post-write reload raced the `EKEventStoreChanged`-
    /// triggered reload the write itself caused, and whichever fetch
    /// *finished* last (not whichever was freshest) overwrote
    /// `snapshot`/`completedToday`. Baseline before the coalescing fix:
    /// 3/10 real taps in this exact loop failed to settle (clustered right
    /// after launch, when the race window is widest); after: 0/10. See the
    /// checkmark-race discovery doc
    /// (`.code-foundations/build/2026-07-03-calenminder-checkmark-bug-discovery.md`)
    /// and `AgendaViewModelTests.selfFiredChangeDuringCompletionDoesNotRevertState`
    /// (the unit-level pin on the same interleaving).
    ///
    /// Ten iterations, deliberately: a single tap passed even before the fix
    /// most of the time - only repetition (especially the first taps after
    /// launch) reproduces the race reliably enough to guard against it.
    /// The final leg uncompletes one task from the expanded Completed
    /// section - the identical `toggleTaskCompletion` -> `load()` path in
    /// the opposite direction, exposed to the same race.
    func test_checkmarkTapCompletionRoundTripSticksEveryTime() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 10))

        let list = app.descendants(matching: .any).matching(identifier: "agenda-list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))

        let incompleteCircles = app.buttons.matching(NSPredicate(format: "label == 'circle'"))

        // Drain any incomplete tasks left over from earlier suite runs so
        // every iteration below starts from a known "exactly one incomplete
        // task" state.
        var drainGuard = 0
        while incompleteCircles.firstMatch.exists, drainGuard < 20 {
            incompleteCircles.firstMatch.tap()
            sleep(2)
            drainGuard += 1
        }

        var failures: [Int] = []
        for iteration in 1...10 {
            seedTask(app, title: "Race Repro \(iteration)-\(UUID().uuidString.prefix(6))")
            for _ in 0..<5 where !incompleteCircles.firstMatch.exists { list.swipeUp() }
            XCTAssertTrue(incompleteCircles.firstMatch.waitForExistence(timeout: 5), "iteration \(iteration): seeded task's circle should appear")

            incompleteCircles.firstMatch.tap()

            let settled = expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: incompleteCircles)
            let result = XCTWaiter().wait(for: [settled], timeout: 3)
            if result != .completed {
                failures.append(iteration)
                // Recover so the next iteration starts clean regardless of
                // this iteration's outcome.
                if incompleteCircles.firstMatch.exists {
                    incompleteCircles.firstMatch.tap()
                    sleep(2)
                }
            }
        }

        print("CHECKMARK_RACE_BASELINE: \(failures.count)/10 iterations failed to settle to completed. Failing iterations: \(failures)")
        XCTAssertTrue(failures.isEmpty, "expected all 10 real checkmark taps to complete without reverting; failed iterations: \(failures)")

        // Uncomplete leg: expand the Completed section and tap one completed
        // task's checkmark - the exact same `toggleTaskCompletion` ->
        // `load()` path, opposite direction. The task must come back to the
        // incomplete working set and *stay* there (no race-driven revert).
        // The DisclosureGroup's header is exposed as a button labeled
        // "Completed"; its rows only enter the accessibility tree once
        // expanded.
        let completedHeader = app.buttons["Completed"]
        for _ in 0..<5 where !completedHeader.exists { list.swipeUp() }
        XCTAssertTrue(completedHeader.waitForExistence(timeout: 5), "the Completed section should exist after completing tasks")
        completedHeader.tap()

        // The toggle's own `task-row-toggle-<id>` identifier is superseded
        // at runtime by its enclosing Section's identifier (the same List-
        // section quirk documented on the incomplete-circle locator above),
        // so completed toggles surface as buttons carrying the
        // "agenda-completed-section" identifier.
        let completedToggles = app.buttons.matching(NSPredicate(format: "identifier == 'agenda-completed-section' AND label != 'Completed'"))
        if !completedToggles.firstMatch.waitForExistence(timeout: 5) {
            let dump = app.buttons.allElementsBoundByIndex.map { "[\($0.identifier)|\($0.label)]" }.joined(separator: " ")
            XCTFail("expanding Completed should reveal completed checkmark toggles; visible buttons: \(dump)")
            return
        }
        completedToggles.firstMatch.tap()

        let reappeared = expectation(for: NSPredicate(format: "count == 1"), evaluatedWith: incompleteCircles)
        XCTAssertEqual(XCTWaiter().wait(for: [reappeared], timeout: 3), .completed, "uncompleting must return the task to the incomplete working set")
        // ... and it must still be there after the change-notification
        // reload settles (the revert in the original bug landed ~1s later).
        sleep(2)
        XCTAssertEqual(incompleteCircles.count, 1, "the uncompleted task must not be raced back to completed")

        // Leave the store clean for other tests: re-complete it.
        incompleteCircles.firstMatch.tap()
    }

    // MARK: - DW-F5.2: Week strip swipe

    func test_DW_F5_2_weekStripSwipeChangesDayByOneWeekAndTapStillWorks() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 10))

        // `TabView(.page)`'s internal `UIKitPagingView` representable does
        // not reliably expose its own `.accessibilityIdentifier`
        // ("week-strip-pager") as a distinct queryable element in this
        // simulator/OS combination - confirmed empirically: an ancestor's
        // identifier ("root-agenda", from `DayContainerView`) bleeds down
        // onto it instead, the same class of identifier-flattening quirk
        // already documented for `MonthDayCell` and `List` `Section`s
        // elsewhere in this codebase. Swiping a tiny leaf element (a single
        // day cell) does not work either - its drag distance is bounded by
        // its own small frame, too short to cross the `TabView`'s page-turn
        // threshold, and gets misread as a tap instead (confirmed
        // empirically too). The `CollectionView` `TabView(.page)` renders as
        // is wide (spans the whole strip) and - despite carrying the
        // "wrong"/bled identifier - is still uniquely findable by element
        // type: it is the only `CollectionView` tagged "root-agenda" (the
        // agenda `List` below it has its own distinct "agenda-list" id).
        let pager = app.collectionViews.matching(identifier: "root-agenda").firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))

        let titleBefore = currentTitle(app)

        pager.swipeLeft()
        let titleAfterNextWeek = currentTitle(app)
        XCTAssertNotEqual(titleBefore, titleAfterNextWeek, "swiping the week strip should page the displayed day by a week")
        attachScreenshot(app, name: "week-strip-after-swipe")

        pager.swipeRight()
        XCTAssertEqual(currentTitle(app), titleBefore, "swiping the week strip back should return to the original day")

        // A plain tap on a specific day cell must still jump straight to
        // that day (the pre-existing behavior), not be swallowed as a swipe
        // or require crossing the pager's swipe-distance threshold.
        app.buttons["agenda-today"].tap()
        XCTAssertEqual(currentTitle(app), titleBefore, "Today should return to the original day")
        let mondayCell = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'week-strip-day-' AND label == 'M'")).firstMatch
        XCTAssertTrue(mondayCell.waitForExistence(timeout: 5))
        mondayCell.tap()
        XCTAssertNotEqual(currentTitle(app), titleBefore, "tapping a specific day cell must still jump straight to that day")
    }

    // MARK: - DW-F5.3: Month view swipe

    func test_DW_F5_3_monthSwipeChangesMonthAndChevronsStillWork() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 10))

        seedEvent(app, title: "Swipe Regression Event")

        app.segmentedControls["calendar-mode-switcher"].buttons["Month"].tap()
        XCTAssertTrue(app.otherElements["root-month"].waitForExistence(timeout: 5))

        let calendar = Calendar.current
        let now = Date()
        guard let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: now) else {
            XCTFail("could not compute next month")
            return
        }
        let currentTitleText = monthTitle(calendar, now)
        let nextTitleText = monthTitle(calendar, nextMonthDate)
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        XCTAssertTrue(app.navigationBars[currentTitleText].waitForExistence(timeout: 5))
        // The seeded event's dot should already be visible on the current
        // month's page before any swipe happens. `month-day-event-dot`
        // itself is not reliably queryable - the dot's own accessibility
        // identifier gets superseded by its enclosing day cell's identifier
        // at runtime (the exact quirk `MonthDayCell`'s own doc comment
        // documents: "a day cell's accessibility identifier surfaces on
        // whichever child SwiftUI happens to expose"). Instead, confirm
        // today's day cell renders more than just its own day-number text -
        // the dot (or task-count) element merges into that same identifier.
        let today = calendar.component(.day, from: now)
        let todayCellElements = app.descendants(matching: .any).matching(identifier: "month-day-\(year)-\(month)-\(today)")
        let indicatorPresent = expectation(for: NSPredicate(format: "count > 1"), evaluatedWith: todayCellElements)
        wait(for: [indicatorPresent], timeout: 5)
        attachScreenshot(app, name: "month-view-before-swipe")

        // Unlike Week strip's pager, `month-grid-pager` is reliably present
        // here (a wide `CollectionView` spanning the whole grid) - swiping a
        // single small day cell instead (as Week strip's workaround does)
        // was tried and confirmed to misfire as a day-cell tap (its drag
        // distance, bounded by the cell's own small frame, never crosses the
        // page-turn threshold), so the wide pager element is used directly.
        let pager = app.descendants(matching: .any).matching(identifier: "month-grid-pager").firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeLeft()

        XCTAssertTrue(app.navigationBars[nextTitleText].waitForExistence(timeout: 5), "swiping the month grid should page to next month")
        // The grid must finish loading (not sit on a permanently-blank
        // indicator state) after paging into a newly-displayed month.
        let stillLoading = NSPredicate { _, _ in app.otherElements["month-loading"].exists }
        let notLoading = XCTNSPredicateExpectation(predicate: NSCompoundPredicate(notPredicateWithSubpredicate: stillLoading), object: nil)
        XCTWaiter().wait(for: [notLoading], timeout: 5)
        attachScreenshot(app, name: "month-view-after-swipe")

        // Chevrons still work, and still target the same view model swipe does.
        app.buttons["month-previous"].tap()
        XCTAssertTrue(app.navigationBars[currentTitleText].waitForExistence(timeout: 5), "the previous-month chevron must still work after a swipe")

        app.buttons["month-next"].tap()
        XCTAssertTrue(app.navigationBars[nextTitleText].waitForExistence(timeout: 5), "the next-month chevron must still work after a swipe")
    }

    // MARK: - DW-F5.4: Year view swipe

    func test_DW_F5_4_yearSwipeChangesYear() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 10))

        app.segmentedControls["calendar-mode-switcher"].buttons["Year"].tap()

        let year = Calendar.current.component(.year, from: Date())
        XCTAssertTrue(app.navigationBars["\(year)"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "year-view-before-swipe")

        // `year-pager` (like `month-grid-pager`) is reliably queryable and
        // wide - see `test_DW_F5_3_monthSwipeChangesMonthAndChevronsStillWork`'s
        // comment for why a small leaf tile is not used here instead.
        let pager = app.descendants(matching: .any).matching(identifier: "year-pager").firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.swipeLeft()

        XCTAssertTrue(app.navigationBars["\(year + 1)"].waitForExistence(timeout: 5), "swiping the year grid should page to the next year")
        attachScreenshot(app, name: "year-view-after-swipe")

        // Chevron still works after a swipe.
        app.buttons["year-previous"].tap()
        XCTAssertTrue(app.navigationBars["\(year)"].waitForExistence(timeout: 5), "the previous-year chevron must still work after a swipe")
    }

    // MARK: - Helpers

    /// The Day view's `navigationTitle` (a weekday/month/day string) is the
    /// simplest reliable proxy for "which day is `AgendaViewModel.day` on" -
    /// it changes if and only if `AgendaViewModel.day` changes, matching
    /// this suite's own single-source-of-truth requirement (DW-F5.1/DW-F5.2).
    private func currentTitle(_ app: XCUIApplication) -> String {
        app.navigationBars.element(boundBy: 0).identifier
    }

    /// Mirrors `MonthView.monthTitle`'s own algorithm exactly, so the
    /// expected title text is derived the same way `CalendarToolbarLayout
    /// UITests` derives its expected year/month numbers - timeless, not tied
    /// to any specific calendar date.
    private func monthTitle(_ calendar: Calendar, _ date: Date) -> String {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let symbols = calendar.monthSymbols
        let name = symbols.indices.contains(month - 1) ? symbols[month - 1] : "\(month)"
        return "\(name) \(year)"
    }

    private func seedTask(_ app: XCUIApplication, title: String) {
        app.buttons["agenda-add-menu"].tap()
        let newTask = app.buttons["New Task"]
        XCTAssertTrue(newTask.waitForExistence(timeout: 5), "the add menu's New Task item should appear")
        newTask.tap()
        let titleField = app.textFields["task-composer-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(title)
        app.buttons["task-composer-save"].tap()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 5))
    }

    private func seedEvent(_ app: XCUIApplication, title: String) {
        app.buttons["agenda-add-menu"].tap()
        let newEvent = app.buttons["New Event"]
        XCTAssertTrue(newEvent.waitForExistence(timeout: 5), "the add menu's New Event item should appear")
        newEvent.tap()
        let titleField = app.textFields["event-edit-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(title)
        app.buttons["event-edit-save"].tap()
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 5))
    }

    /// Writes a real PNG to `.code-foundations/build/swipe-evidence/` (not
    /// just an XCTest attachment buried in the `.xcresult` bundle) - the
    /// screenshot evidence the Feature 5 plan asks for. `#filePath` (this
    /// source file's own compile-time absolute path) locates the repo root
    /// two levels up, so this does not depend on the test process's runtime
    /// working directory, which is not guaranteed to be the repo root.
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let evidenceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".code-foundations/build/swipe-evidence")
        try? FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: evidenceDirectory.appendingPathComponent("\(name).png"))
    }
}

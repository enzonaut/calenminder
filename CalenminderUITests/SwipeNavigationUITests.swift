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

        // A run-unique title, not a fixed literal: this simulator's real
        // Reminders store keeps whatever other incomplete tasks pre-existed
        // (this suite's own past runs, manual verification, or - on a real
        // device - the user's own data), so the row this test taps must be
        // identified by something only *this* run created, never "whichever
        // circle happens to be first in the list" (see the class-level
        // pollution note on `circleButton(forRowTitled:in:)`).
        let title = uniqueTitle("Swipe Regression Task")
        seedTask(app, title: title)

        let titleBefore = currentTitle(app)
        let list = app.descendants(matching: .any).matching(identifier: "agenda-list").firstMatch
        // The Tasks section can be scrolled below the initial viewport (a
        // long list of events, or many previously-seeded tasks, ahead of
        // it) - List virtualizes off-screen rows out of the accessibility
        // tree entirely, so scroll down until *this* row (found by its own
        // unique title, not any incomplete row) is visible.
        let circle = circleButton(forRowTitled: title, in: app)
        for _ in 0..<10 where !circle.exists { list.swipeUp() }
        XCTAssertTrue(circle.waitForExistence(timeout: 5), "seeded task's own checkmark button should exist")

        waitForSteadyFrame(of: circle)
        tapWhenReady(circle)
        // Give any (correctly-scoped, horizontal-dominant) gesture recognizer
        // time to have misfired if it were going to.
        sleep(1)

        XCTAssertEqual(currentTitle(app), titleBefore, "tapping the checkmark must not page the displayed day")
        XCTAssertTrue(app.otherElements["root-agenda"].exists, "the agenda must still be showing (no crash) after the tap")
        // The tap must land as a button tap (not be consumed by any gesture):
        // the tapped task completes and *its own* row's circle (found again
        // by the same unique title, never any other row) stops existing.
        // This assertion previously checked the circle was *still hittable*
        // - which only ever passed because the completion race (since fixed)
        // could leave the tapped task incomplete; the intended behavior is
        // the opposite.
        let completed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: circle)
        XCTAssertEqual(XCTWaiter().wait(for: [completed], timeout: 6), .completed, "the tapped checkmark's task should complete, proving the tap was not consumed by a swipe")
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

        // No pre-drain of "whatever is incomplete": this simulator's real
        // Reminders store carries however much pre-existing data other runs,
        // manual verification, or (on a real device) the user's own tasks
        // left behind - blindly tapping every incomplete circle in the list
        // would complete tasks this test never created, which is both unsafe
        // and (with enough accumulated rows) too slow to bound with a fixed
        // retry count. Each iteration instead seeds one run-unique task and
        // only ever locates/taps *that* row's own circle, so correctness
        // never depends on how much other data is present.
        var failures: [Int] = []
        var lastTitle = ""
        for iteration in 1...10 {
            let title = uniqueTitle("Race Repro \(iteration)")
            lastTitle = title
            seedTask(app, title: title)
            let circle = circleButton(forRowTitled: title, in: app)
            for _ in 0..<10 where !circle.exists { list.swipeUp() }
            XCTAssertTrue(circle.waitForExistence(timeout: 5), "iteration \(iteration): seeded task's own circle should appear")

            // The seed's own write fires `EKEventStoreChanged`-driven reloads
            // that re-diff the `List` right around now - a tap synthesized
            // while the row is being replaced under it gets swallowed by the
            // recycled row (button action never fires), which reads exactly
            // like the revert this test guards against but is pure tap-timing.
            // Confirmed empirically on a data-heavy store (wider diff window):
            // iteration 1, right after launch, intermittently failed with the
            // circle never disappearing, and a plain re-tap completed it -
            // i.e. the first tap had landed on a mid-diff row. Waiting for the
            // row's frame to hold still first removes that window without
            // weakening the actual assertion (a genuine revert still fails).
            waitForSteadyFrame(of: circle)
            tapWhenReady(circle)

            // 6s, not the original flat query's 3s: scoping every poll to
            // this row's own `Cell` (via `.cells.containing(...)`, see
            // `circleButton(forRowTitled:in:)`) costs several extra
            // accessibility-snapshot round trips per check compared to a
            // flat `app.buttons.matching(...)` query - measured empirically
            // to occasionally push a real, on-time completion just past a
            // 3s budget purely on query overhead, reporting a false failure
            // for an iteration that actually settled correctly. The
            // assertion itself (no reversion) is unchanged; this only gives
            // the pricier-but-correctly-scoped check enough real time to
            // observe the same outcome the original, cheaper query would
            // have seen sooner.
            let settled = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: circle)
            let result = XCTWaiter().wait(for: [settled], timeout: 6)
            if result != .completed {
                failures.append(iteration)
                // Evidence for triage: what the screen actually showed when
                // the circle failed to disappear.
                attachScreenshot(app, name: "race-iteration-\(iteration)-failed")
                // Recover so the next iteration starts clean regardless of
                // this iteration's outcome.
                if circle.exists {
                    tapWhenReady(circle)
                    sleep(2)
                }
            }
        }

        print("CHECKMARK_RACE_BASELINE: \(failures.count)/10 iterations failed to settle to completed. Failing iterations: \(failures)")
        XCTAssertTrue(failures.isEmpty, "expected all 10 real checkmark taps to complete without reverting; failed iterations: \(failures)")

        // Uncomplete leg: expand the Completed section and tap the *last*
        // iteration's own completed task's checkmark, found again by its
        // unique title - the exact same `toggleTaskCompletion` -> `load()`
        // path, opposite direction. The task must come back to the
        // incomplete working set and *stay* there (no race-driven revert).
        // The DisclosureGroup's header is exposed as a button labeled
        // "Completed"; its rows only enter the accessibility tree once
        // expanded.
        let completedHeader = app.buttons["Completed"]
        for _ in 0..<10 where !completedHeader.exists { list.swipeUp() }
        XCTAssertTrue(completedHeader.waitForExistence(timeout: 5), "the Completed section should exist after completing tasks")
        tapWhenReady(completedHeader)

        // The toggle's own `task-row-toggle-<id>` identifier is superseded
        // at runtime by its enclosing Section's identifier (the same List-
        // section quirk documented on `circleButton(forRowTitled:in:)`), so
        // scope by the row containing this run's own title, same as every
        // other lookup in this test - never any completed row at large,
        // which (with enough accumulated history in this store) could be
        // someone else's task entirely.
        // The Completed section lists completed-today tasks oldest-first
        // (confirmed empirically via a tree dump: an earlier run's
        // "Race Repro 1/2/..." rows render at the top, the just-completed
        // probe at the very bottom, virtualized out of the tree) - so this
        // run's own row sits at the END of *every* completed-today row the
        // store has accumulated, which on a shared/lived-in store can be many
        // screenfuls deep. Fast-swipe with a generous budget until the row
        // enters the rendered buffer; a fixed ~10-swipe budget was measured
        // to run out once enough prior runs' completions had piled up.
        let completedToggle = completedToggleButton(forRowTitled: lastTitle, in: app)
        var scrollBudget = 40
        while !completedToggle.exists, scrollBudget > 0 {
            list.swipeUp(velocity: .fast)
            scrollBudget -= 1
        }
        if !completedToggle.waitForExistence(timeout: 5) {
            let dump = app.buttons.allElementsBoundByIndex.map { "[\($0.identifier)|\($0.label)]" }.joined(separator: " ")
            XCTFail("expanding Completed should reveal this run's own completed toggle for '\(lastTitle)'; visible buttons: \(dump)")
            return
        }
        // The DisclosureGroup expansion animates its rows in - same
        // swallowed-tap exposure as the iteration loop's post-seed tap.
        waitForSteadyFrame(of: completedToggle)
        tapWhenReady(completedToggle)

        // The uncompleted row returns to the Tasks section, which sits
        // *above* the Completed section this leg just scrolled down to - and
        // `List` virtualizes off-screen rows out of the accessibility tree
        // entirely (the same virtualization documented on the seeded-task
        // scroll loops above), so `exists` on the row's circle stays false
        // from down here even when the uncompletion succeeded. Scroll back
        // up until the row is actually on screen before asserting on it -
        // confirmed empirically: with enough completed rows accumulated from
        // earlier runs pushing the Tasks section further off-screen, the
        // assert-without-scrolling version of this leg failed exactly here.
        // Same generous fast-swipe budget as the downward hunt above: the
        // way back up crosses that entire accumulated Completed section.
        let circle = circleButton(forRowTitled: lastTitle, in: app)
        var upBudget = 40
        while !circle.exists, upBudget > 0 {
            list.swipeDown(velocity: .fast)
            upBudget -= 1
        }
        let reappeared = expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: circle)
        XCTAssertEqual(XCTWaiter().wait(for: [reappeared], timeout: 6), .completed, "uncompleting must return the task to the incomplete working set")
        // ... and it must still be there after the change-notification
        // reload settles (the revert in the original bug landed ~1s later).
        sleep(2)
        XCTAssertTrue(circle.exists, "the uncompleted task must not be raced back to completed")

        // Leave the store clean for other tests: re-complete it.
        waitForSteadyFrame(of: circle)
        tapWhenReady(circle)
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

        // Run-unique title: previous runs of this exact test (this suite has
        // no delete affordance to clean up after itself before this fix) had
        // left over a dozen-plus same-titled "Swipe Regression Event" rows in
        // the simulator's real Default calendar - harmless to this test's own
        // assertions (which never count events), but the title still needs
        // to be unique so `deleteSeededEvent` below can find and remove
        // *this* run's own event without touching anyone else's.
        let eventTitle = uniqueTitle("Swipe Regression Event")
        seedEvent(app, title: eventTitle)
        defer { deleteSeededEvent(app, title: eventTitle) }

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

        // Chevrons still work, and still target the same view model swipe
        // does. `tapWhenReady` (not a bare `.tap()`) waits for `isHittable`,
        // not just `.exists` - a plain tap immediately after the swipe's
        // page-turn/relayout settled was observed empirically to sometimes
        // land on a toolbar button before its activation point was valid
        // ("Computed hit point {-1, -1} after scrolling to visible"), a
        // transient layout race independent of any seeded data.
        tapWhenReady(app.buttons["month-previous"])
        XCTAssertTrue(app.navigationBars[currentTitleText].waitForExistence(timeout: 5), "the previous-month chevron must still work after a swipe")

        tapWhenReady(app.buttons["month-next"])
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
        tapWhenReady(app.buttons["agenda-add-menu"])
        let newTask = app.buttons["New Task"]
        XCTAssertTrue(newTask.waitForExistence(timeout: 5), "the add menu's New Task item should appear")
        tapWhenReady(newTask)
        let titleField = app.textFields["task-composer-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        tapWhenReady(titleField)
        titleField.typeText(title)
        tapWhenReady(app.buttons["task-composer-save"])
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 5))
    }

    private func seedEvent(_ app: XCUIApplication, title: String) {
        tapWhenReady(app.buttons["agenda-add-menu"])
        let newEvent = app.buttons["New Event"]
        XCTAssertTrue(newEvent.waitForExistence(timeout: 5), "the add menu's New Event item should appear")
        tapWhenReady(newEvent)
        let titleField = app.textFields["event-edit-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        tapWhenReady(titleField)
        titleField.typeText(title)
        tapWhenReady(app.buttons["event-edit-save"])
        XCTAssertTrue(app.otherElements["root-agenda"].waitForExistence(timeout: 5))
    }

    /// A per-invocation-unique title built from `base`. Every item this suite
    /// seeds into the simulator's real Calendar/Reminders stores uses one of
    /// these, never a fixed literal - see the discovery doc
    /// (`.code-foundations/build/2026-07-04-calenminder-uitest-flake-discovery.md`)
    /// for why a fixed literal title let this suite's own repeated runs
    /// accumulate indistinguishable duplicates over time, which in turn made
    /// "find the row this test just created" ambiguous with "find some row
    /// left over from an earlier run" - a distinction none of this suite's
    /// assertions can afford to lose.
    private func uniqueTitle(_ base: String) -> String {
        "\(base) \(UUID().uuidString.prefix(8))"
    }

    /// Waits for `element` to exist *and* be hittable before tapping -
    /// XCUIElement.tap() alone only waits for existence, not for the
    /// element's activation point to actually be valid. A bare `.tap()`
    /// immediately after a sheet presentation/dismissal or a page-turn
    /// relayout was observed empirically to intermittently fail with
    /// "Activation point invalid" / "Computed hit point {-1, -1}" even
    /// though `.exists` was already `true` - a transient timing race
    /// unrelated to how much data is seeded, which this suite's own launch,
    /// menu, and chevron taps are equally exposed to.
    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(element) should exist before tapping")
        if !element.isHittable {
            let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
            _ = XCTWaiter().wait(for: [hittable], timeout: timeout)
        }
        element.tap()
    }

    /// Waits until `element`'s frame reports the same value on two
    /// consecutive samples and the element is hittable - i.e. the `List` has
    /// finished any in-flight diff/relayout around it. A tap synthesized
    /// while a row is being replaced (a store-change reload re-diffing the
    /// list) can be delivered to the recycled row and silently fire nothing;
    /// see the call site in the checkmark-race test for the empirical trace.
    /// Best-effort: on timeout it simply returns (the subsequent tap then
    /// behaves exactly as it would have without this wait).
    private func waitForSteadyFrame(of element: XCUIElement, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        // `.frame` on an element with no current match hard-fails the test
        // ("Failed to get matching snapshot: No matches found..."), and a
        // mid-diff row can transiently vanish from the tree - so re-check
        // `exists` before every frame read.
        var previous = element.exists ? element.frame : .null
        while Date() < deadline {
            usleep(300_000)
            let current = element.exists ? element.frame : .null
            if current == previous, !current.isEmpty, !current.isNull, element.isHittable { return }
            previous = current
        }
    }

    /// Locates the incomplete-task checkmark `Button` for the row whose
    /// title is exactly `title` - scoped to that one `List` row (a `Cell`
    /// ancestor, confirmed empirically via the accessibility tree), never
    /// "whichever circle-labeled button happens to be first in the list".
    ///
    /// This distinction matters because every incomplete task's checkmark
    /// image renders with the *identical* accessibility label ("circle" -
    /// see the label-based workaround note above), so on a store carrying
    /// any pre-existing incomplete tasks (this suite's own past runs before
    /// this fix routinely left over a hundred-plus; a real device has the
    /// user's own pending reminders), matching on label alone across the
    /// whole app can tap - or count - a row this test never created. Scoping
    /// to the row containing this run's own unique title keeps every
    /// assertion correct regardless of how much other data exists.
    private func circleButton(forRowTitled title: String, in app: XCUIApplication) -> XCUIElement {
        let row = app.cells.containing(NSPredicate(format: "label == %@", title)).firstMatch
        return row.buttons.matching(NSPredicate(format: "label == 'circle'")).firstMatch
    }

    /// Same scoping as `circleButton(forRowTitled:in:)`, for a row inside the
    /// expanded "Completed" `DisclosureGroup` - its toggle buttons carry the
    /// bled `"agenda-completed-section"` identifier (see the checkmark
    /// test's own comment), so label/identifier alone cannot distinguish one
    /// completed row from another; only the row's own title can.
    private func completedToggleButton(forRowTitled title: String, in app: XCUIApplication) -> XCUIElement {
        let row = app.cells.containing(NSPredicate(format: "label == %@", title)).firstMatch
        return row.buttons.matching(NSPredicate(format: "identifier == 'agenda-completed-section'")).firstMatch
    }

    /// Best-effort cleanup for an event this suite created via `seedEvent`:
    /// switches back to Day view, opens the event's own detail sheet (found
    /// by its unique title, never any other event), and deletes it through
    /// the app's existing `event-detail-delete` affordance. Tasks have no
    /// equivalent delete path in this app (`TaskStoring` intentionally has no
    /// delete member - only completion), so this only applies to events;
    /// swallows its own failures (best-effort teardown must never mask the
    /// test's actual assertions with an unrelated teardown failure).
    private func deleteSeededEvent(_ app: XCUIApplication, title: String) {
        let mode = app.segmentedControls["calendar-mode-switcher"]
        if mode.buttons["Day"].exists { mode.buttons["Day"].tap() }
        let list = app.descendants(matching: .any).matching(identifier: "agenda-list").firstMatch
        let row = app.cells.containing(NSPredicate(format: "label == %@", title)).firstMatch
        for _ in 0..<10 where !row.exists { list.swipeUp() }
        guard row.waitForExistence(timeout: 5) else { return }
        row.tap()
        let deleteButton = app.buttons["event-detail-delete"]
        guard deleteButton.waitForExistence(timeout: 5) else { return }
        deleteButton.tap()
        let confirm = app.buttons["This Event"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
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

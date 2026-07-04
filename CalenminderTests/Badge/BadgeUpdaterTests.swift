import Testing
import Foundation
@testable import CalenminderKit

/// Feature 3: `BadgeUpdater` orchestration (DW-F3.2, DW-F3.3). The
/// counting rule itself (today incomplete + overdue, completed excluded,
/// dedup) is `AgendaService.badgeCount(asOf:)`'s job and is tested directly
/// against fake stores in `AgendaServiceTests` (DW-F3.1) - these tests only
/// need enough store state to prove `BadgeUpdater` wires authorization,
/// counting, and applying together correctly.
struct BadgeUpdaterTests {
    let cal = Fixture.calendar("America/New_York")
    var today: DayStamp { DayStamp(year: 2026, month: 7, day: 3) }

    private func makeUpdater(
        tasks: FakeTaskStore = FakeTaskStore(),
        badgeSetter: FakeBadgeSetter = FakeBadgeSetter()
    ) -> BadgeUpdater {
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: tasks)
        return BadgeUpdater(
            agendaService: service,
            badgeSetting: badgeSetter,
            calendar: cal,
            now: { Fixture.date(self.cal, 2026, 7, 3, 9) }
        )
    }

    @Test("DW-F3.2: updateBadge applies the computed incomplete count")
    func test_DW_F3_2_updateBadgeAppliesComputedCount() async {
        let tasks = FakeTaskStore()
        tasks.tasks = [
            Fixture.task(id: "today", due: today),
            Fixture.task(id: "overdue", due: DayStamp(year: 2026, month: 7, day: 1)),
            Fixture.task(id: "done-today", due: today, completed: true),
        ]
        let badgeSetter = FakeBadgeSetter()
        let updater = makeUpdater(tasks: tasks, badgeSetter: badgeSetter)

        await updater.updateBadge()

        #expect(badgeSetter.appliedCounts == [2])
    }

    @Test("DW-F3.1/DW-F3.2: a zero incomplete count clears the badge (applies 0)")
    func test_DW_F3_1_zeroCountAppliesZeroToClearBadge() async {
        let badgeSetter = FakeBadgeSetter()
        let updater = makeUpdater(badgeSetter: badgeSetter)

        await updater.updateBadge()

        #expect(badgeSetter.appliedCounts == [0])
    }

    @Test("DW-F3.3: a store failure (e.g. Reminders access denied) never throws - it degrades to badge 0")
    func test_DW_F3_3_updateBadgeNeverThrowsWhenCountingFails() async {
        let tasks = FakeTaskStore()
        tasks.fetchError = TestError.boom
        let badgeSetter = FakeBadgeSetter()
        let updater = makeUpdater(tasks: tasks, badgeSetter: badgeSetter)

        await updater.updateBadge() // must not throw / crash

        #expect(badgeSetter.appliedCounts == [0])
    }

    @Test("DW-F3.3: authorization is requested on every call, not just the first - proves re-evaluation on later foregrounds")
    func test_DW_F3_3_requestsAuthorizationOnEveryCall() async {
        let badgeSetter = FakeBadgeSetter()
        let updater = makeUpdater(badgeSetter: badgeSetter)

        await updater.updateBadge()
        await updater.updateBadge()
        await updater.updateBadge()

        #expect(badgeSetter.requestAuthorizationCallCount == 3)
        #expect(badgeSetter.appliedCounts.count == 3)
    }
}

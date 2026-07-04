import Testing
import Foundation
import BackgroundTasks
@testable import Calenminder
@testable import CalenminderKit

/// Feature 3: `BadgeRefreshScheduler` (DW-F3.4). `BGTaskScheduler`'s real
/// `register`/`submit` cannot be meaningfully exercised in a unit-test host
/// (no real app launch, and `BGTask`/`BGAppRefreshTask` have no public
/// initializer - see `BackgroundTaskScheduling`'s doc comment), so these
/// tests verify the call shape `BadgeRefreshScheduler` produces against
/// `FakeBackgroundTaskScheduler`, not the launch-handler closure's body.
struct BadgeRefreshSchedulerTests {
    private func makeScheduler(fake: FakeBackgroundTaskScheduler = FakeBackgroundTaskScheduler()) -> BadgeRefreshScheduler {
        let service = AgendaService(eventStore: FakeEventStore(), taskStore: FakeTaskStore())
        let badgeUpdater = BadgeUpdater(agendaService: service, badgeSetting: FakeBadgeSetter())
        return BadgeRefreshScheduler(badgeUpdater: badgeUpdater, scheduler: fake)
    }

    @Test("DW-F3.4: register() registers the fixed task identifier")
    func test_DW_F3_4_registerRegistersTheTaskIdentifier() {
        let fake = FakeBackgroundTaskScheduler()
        let scheduler = makeScheduler(fake: fake)

        scheduler.register()

        #expect(fake.registeredIdentifiers == [BadgeRefreshScheduler.taskIdentifier])
        #expect(fake.capturedLaunchHandler != nil)
    }

    @Test("DW-F3.4: schedule() submits a BGAppRefreshTaskRequest for the same identifier")
    func test_DW_F3_4_scheduleSubmitsARequestForTheTaskIdentifier() {
        let fake = FakeBackgroundTaskScheduler()
        let scheduler = makeScheduler(fake: fake)

        scheduler.schedule()

        #expect(fake.submittedIdentifiers == [BadgeRefreshScheduler.taskIdentifier])
    }

    @Test("DW-F3.4: schedule() is safe to call repeatedly (each fire reschedules)")
    func test_DW_F3_4_scheduleIsSafeToCallRepeatedly() {
        let fake = FakeBackgroundTaskScheduler()
        let scheduler = makeScheduler(fake: fake)

        scheduler.schedule()
        scheduler.schedule()
        scheduler.schedule()

        #expect(fake.submittedIdentifiers == Array(repeating: BadgeRefreshScheduler.taskIdentifier, count: 3))
    }

    @Test("DW-F3.4: a failed submit is swallowed, not thrown or crashed")
    func test_DW_F3_4_failedSubmitIsSwallowed() {
        let fake = FakeBackgroundTaskScheduler()
        fake.submitError = TestError.boom
        let scheduler = makeScheduler(fake: fake)

        scheduler.schedule() // must not throw / crash

        #expect(fake.submittedIdentifiers.isEmpty)
    }
}

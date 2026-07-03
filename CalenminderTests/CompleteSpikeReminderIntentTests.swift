import Testing
import EventKit
@testable import CalenminderIntents

/// Coverage beyond the DW floor: the spike intent's graceful-failure paths.
/// The unit-test process never holds Reminders authorization (it is a
/// distinct, unprompted bundle identity), so `completeSpikeReminder()` must
/// take the `.accessDenied` branch and return cleanly -- never throw, never
/// force-unwrap, never crash -- exercising the same "graceful no-op" shape
/// Phase 5's `CompleteTaskIntent` will need for stale/deleted tasks (DW-5.5).
struct CompleteSpikeReminderIntentTests {
    @Test("completeSpikeReminder() is a graceful no-op when Reminders access is not granted")
    func completeSpikeReminderWithoutAccessIsGracefulNoOp() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        // Guard the assumption this test relies on: an unprompted test
        // process has no Reminders access. If a prior test run in this
        // simulator granted access to this exact bundle identity, skip
        // rather than assert a false premise.
        guard status != .fullAccess else {
            return
        }

        let outcome = await CompleteSpikeReminderIntent.completeSpikeReminder()
        #expect(outcome == .accessDenied)
    }

    @Test("Intent outcome cases round-trip through their raw string value")
    func outcomeRawValueRoundTrips() {
        let allCases: [CompleteSpikeReminderIntent.Outcome] = [
            .accessDenied, .listNotSeeded, .reminderNotFound, .saveFailed, .success,
        ]
        for outcome in allCases {
            #expect(CompleteSpikeReminderIntent.Outcome(rawValue: outcome.rawValue) == outcome)
        }
    }
}

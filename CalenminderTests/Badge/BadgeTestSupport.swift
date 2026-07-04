import Foundation
import BackgroundTasks
@testable import CalenminderKit
@testable import Calenminder

/// Fake `BadgeSetting`. See `FakeWidgetReloader` (`AgendaTestSupport.swift`)
/// for the precedent this mirrors - records call shape only, no behavior
/// beyond what a test needs.
final class FakeBadgeSetter: BadgeSetting {
    private(set) var requestAuthorizationCallCount = 0
    private(set) var appliedCounts: [Int] = []

    func requestAuthorizationIfNeeded() async {
        requestAuthorizationCallCount += 1
    }

    func applyBadgeCount(_ count: Int) async {
        appliedCounts.append(count)
    }
}

/// Fake `BackgroundTaskScheduling`. `BGTaskScheduler`'s real
/// `register`/`submit` cannot be exercised in a unit-test host in any
/// meaningful way (registration fails outside a real, launched app; a real
/// `BGTask` cannot be constructed at all), so this records exactly the call
/// shape `BadgeRefreshScheduler` produces: which identifier was registered,
/// and the identifiers of every submitted request.
final class FakeBackgroundTaskScheduler: BackgroundTaskScheduling {
    private(set) var registeredIdentifiers: [String] = []
    private(set) var capturedLaunchHandler: ((BGTask) -> Void)?
    private(set) var submittedIdentifiers: [String] = []
    var submitError: Error?

    @discardableResult
    func register(forTaskWithIdentifier identifier: String, using queue: DispatchQueue?, launchHandler: @escaping (BGTask) -> Void) -> Bool {
        registeredIdentifiers.append(identifier)
        capturedLaunchHandler = launchHandler
        return true
    }

    func submit(_ taskRequest: BGTaskRequest) throws {
        if let submitError { throw submitError }
        submittedIdentifiers.append(taskRequest.identifier)
    }
}

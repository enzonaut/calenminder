import SwiftUI
@preconcurrency import EventKit
import CalenminderKit
import os

/// App entry point. Phase 1 scope only: request the two full-access
/// permissions the whole app needs (widgets cannot prompt, so this must
/// happen here first) and seed the throwaway spike reminder the widget's
/// `CompleteSpikeReminderIntent` completes. Real onboarding UI is Phase 4.
@main
struct CalenminderApp: App {
    @StateObject private var launchCoordinator = LaunchCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView(coordinator: launchCoordinator)
                .task {
                    await launchCoordinator.requestAccessAndSeedSpike()
                }
        }
    }
}

/// PSEUDOCODE:
///   Request full access to Reminders (async).
///   If granted:
///       Ensure the "Calenminder Spike" list exists (create if missing).
///       Ensure the spike reminder exists in that list, not completed.
///       If seeding fails -> publish a typed error state (never silent).
///   Request full access to Calendars (async) -- both usage keys are
///   declared (DW-1.3) and the plan requires both permissions established
///   before Phase 5 needs them; the constraint text singles out Reminders
///   because the spike itself only needs Reminders.
///   Publish status for ContentView so a screenshot proves the request/seed
///   happened.
@MainActor
final class LaunchCoordinator: ObservableObject {
    enum Status: Equatable {
        case idle
        case requestingAccess
        case ready(seededReminderTitle: String)
        case error(String)
    }

    @Published private(set) var status: Status = .idle

    private let logger = Logger(subsystem: "com.enzonaut.calenminder", category: "LaunchCoordinator")
    private let store = EKEventStore()

    func requestAccessAndSeedSpike() async {
        status = .requestingAccess

        do {
            let remindersGranted = try await store.requestFullAccessToReminders()
            guard remindersGranted else {
                status = .error("Reminders full access denied")
                return
            }

            try await seedSpikeReminder()

            // Calendars access is requested too: both usage-description keys
            // are declared (DW-1.3), and Phase 5's Lock Screen widget needs
            // Calendars access established ahead of time, same as Reminders.
            _ = try? await store.requestFullAccessToEvents()

            status = .ready(seededReminderTitle: SpikeConfig.reminderTitle)
        } catch {
            logger.error("launch coordination failed: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
        }
    }

    private func seedSpikeReminder() async throws {
        let list = try ensureSpikeList()

        let predicate = store.predicateForReminders(in: [list])
        let existing = await fetchReminders(matching: predicate)

        if existing.contains(where: { $0.title == SpikeConfig.reminderTitle && !$0.isCompleted }) {
            return
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = SpikeConfig.reminderTitle
        reminder.calendar = list
        try store.save(reminder, commit: true)
    }

    private func ensureSpikeList() throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == SpikeConfig.listName }) {
            return existing
        }

        guard let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        else {
            throw LaunchCoordinatorError.noReminderSourceAvailable
        }

        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = SpikeConfig.listName
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }

    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }
}

enum LaunchCoordinatorError: Error, LocalizedError {
    case noReminderSourceAvailable

    var errorDescription: String? {
        switch self {
        case .noReminderSourceAvailable:
            return "No Reminders source available to create the spike list."
        }
    }
}

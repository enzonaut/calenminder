import SwiftUI
import CalenminderKit

/// Phase 1 placeholder screen. Shows the launch coordinator's status (proof
/// the permission request + spike seeding ran) and the last outcome the
/// widget's `CompleteSpikeReminderIntent` recorded, for screenshot evidence.
/// Real agenda UI is Phase 4 scope.
struct ContentView: View {
    @ObservedObject var coordinator: LaunchCoordinator

    var body: some View {
        VStack(spacing: 16) {
            Text("Calenminder")
                .font(.title)
                .accessibilityIdentifier("app-title")

            statusView
                .accessibilityIdentifier("launch-status")

            Divider()

            spikeOutcomeView
                .accessibilityIdentifier("spike-outcome")
        }
        .padding()
    }

    @ViewBuilder
    private var statusView: some View {
        switch coordinator.status {
        case .idle:
            Text("Idle")
        case .requestingAccess:
            Text("Requesting access…")
        case .ready(let title):
            Text("Ready — seeded \"\(title)\"")
        case .error(let message):
            Text("Error: \(message)")
                .foregroundStyle(.red)
        }
    }

    private var spikeOutcomeView: some View {
        let defaults = AppGroup.sharedDefaults
        let outcomeKey = "spike.lastOutcome"
        let timestampKey = "spike.lastOutcomeAt"
        let outcome = defaults?.string(forKey: outcomeKey) ?? "none yet"
        let timestamp = (defaults?.object(forKey: timestampKey) as? Date)?.formatted() ?? "—"
        return VStack {
            Text("Last widget spike outcome: \(outcome)")
            Text("At: \(timestamp)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView(coordinator: LaunchCoordinator())
}

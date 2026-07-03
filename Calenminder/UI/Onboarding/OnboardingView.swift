import SwiftUI
import UIKit

/// Permission gate shown until both Calendars and Reminders full access are
/// granted. Real onboarding UI (Phase 4 scope) - replaces the Phase 1
/// placeholder.
struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Calenminder")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("onboarding-title")

            content

            Spacer()
            Spacer()
        }
        .padding()
        .task { await viewModel.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .checking:
            ProgressView("Requesting access…")
                .accessibilityIdentifier("onboarding-checking")
        case .needsPermission(let message):
            VStack(spacing: 12) {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding-message")

                Button("Open Settings") {
                    openSettings()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboarding-open-settings")

                Button("Try Again") {
                    Task { await viewModel.start() }
                }
                .accessibilityIdentifier("onboarding-retry")
            }
            .padding(.horizontal)
        case .granted:
            // RootView swaps to AgendaView once this fires; nothing to show
            // here (avoids a visible flash of "granted" text).
            EmptyView()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    OnboardingView(viewModel: OnboardingViewModel(agendaService: AppEnvironment.live().agendaService))
}

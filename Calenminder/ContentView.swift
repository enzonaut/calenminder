import SwiftUI
import CalenminderKit

/// The app's composition root: gates the agenda behind onboarding,
/// refreshes on foreground, and routes incoming `calenminder://` deep links
/// to the right detail screen (or a not-found state, never a crash).
struct ContentView: View {
    @StateObject private var onboarding: OnboardingViewModel
    @StateObject private var agenda: AgendaViewModel
    @StateObject private var router = DeepLinkRouter()

    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment) {
        _onboarding = StateObject(wrappedValue: OnboardingViewModel(agendaService: environment.agendaService))
        _agenda = StateObject(wrappedValue: AgendaViewModel(agendaService: environment.agendaService))
    }

    var body: some View {
        Group {
            if onboarding.state == .granted {
                AgendaView(viewModel: agenda)
                    .accessibilityIdentifier("root-agenda")
            } else {
                OnboardingView(viewModel: onboarding)
                    .accessibilityIdentifier("root-onboarding")
            }
        }
        .onChange(of: onboarding.state) { _, newValue in
            guard newValue == .granted else { return }
            Task { await agenda.load() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await onboarding.start()
                if onboarding.state == .granted {
                    await agenda.handleForeground()
                }
            }
        }
        .onOpenURL { url in router.handle(url: url) }
        .sheet(isPresented: Binding(
            get: { router.route != nil },
            set: { isPresented in if !isPresented { router.dismiss() } }
        )) {
            routeContent
        }
    }

    @ViewBuilder
    private var routeContent: some View {
        switch router.route {
        case .eventDetail(let externalIdentifier, let occurrenceDate):
            EventDetailView(
                viewModel: EventDetailViewModel(agenda: agenda, externalIdentifier: externalIdentifier, occurrenceDate: occurrenceDate),
                agenda: agenda,
                onDismiss: { router.dismiss() }
            )
        case .taskDetail(let externalIdentifier):
            TaskDetailView(
                viewModel: TaskDetailViewModel(agenda: agenda, externalIdentifier: externalIdentifier),
                onDismiss: { router.dismiss() }
            )
        case .notFound, .none:
            NotFoundView(onDismiss: { router.dismiss() })
        }
    }
}

#Preview {
    ContentView(environment: .live())
}

import SwiftUI
import CalenminderKit

/// The app's composition root: gates the agenda behind onboarding,
/// refreshes on foreground, and routes incoming `calenminder://` deep links
/// to the right detail screen (or a not-found state, never a crash).
struct ContentView: View {
    @StateObject private var onboarding: OnboardingViewModel
    @StateObject private var agenda: AgendaViewModel
    @StateObject private var navigation = CalendarNavigationViewModel()
    @StateObject private var router = DeepLinkRouter()
    @State private var yearViewModel: YearViewModel
    @State private var monthViewModel: MonthViewModel

    private let agendaService: AgendaService
    /// Feature 3: opportunistic BGAppRefreshTask wrapper - registered at app
    /// launch (`CalenminderApp.init()`) and (re)scheduled here on every
    /// backgrounding, which is the natural point: the request only ever
    /// fires once the app is no longer foreground anyway.
    private let badgeRefreshScheduler: BadgeRefreshScheduler

    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment) {
        agendaService = environment.agendaService
        _onboarding = StateObject(wrappedValue: OnboardingViewModel(agendaService: environment.agendaService))
        _agenda = StateObject(wrappedValue: AgendaViewModel(agendaService: environment.agendaService, badgeUpdater: environment.badgeUpdater))
        _yearViewModel = State(wrappedValue: YearViewModel())
        _monthViewModel = State(wrappedValue: MonthViewModel(agendaService: environment.agendaService))
        badgeRefreshScheduler = BadgeRefreshScheduler(badgeUpdater: environment.badgeUpdater)
    }

    var body: some View {
        Group {
            if onboarding.state == .granted {
                calendarContent
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
            switch newPhase {
            case .active:
                Task {
                    await onboarding.start()
                    if onboarding.state == .granted {
                        await agenda.handleForeground()
                    } else {
                        // Onboarding isn't granted yet, so the full agenda
                        // load stays skipped exactly as before - but the
                        // badge is a separate permission (notifications,
                        // not Calendars/Reminders), so it's still worth a
                        // lazy authorization check/recompute on every
                        // foreground even before onboarding finishes.
                        // `handleBackground()` is really just "refresh the
                        // badge alone," which is exactly what's needed here.
                        await agenda.handleBackground()
                    }
                }
            case .background:
                Task { await agenda.handleBackground() }
                badgeRefreshScheduler.schedule()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        // Rebuild the Year/Month child view models only when drill-down or
        // the switcher hands them a genuinely different anchor - never on
        // every unrelated body re-evaluation, which would otherwise reload
        // Month view in a loop each time `agenda` publishes.
        .onChange(of: navigation.mode) { _, newMode in
            switch newMode {
            case .year(let year):
                if yearViewModel.year != year { yearViewModel = YearViewModel(year: year) }
            case .month(let month):
                if monthViewModel.month != month {
                    monthViewModel = MonthViewModel(agendaService: agendaService, month: month)
                }
            case .day:
                break
            }
        }
        .onOpenURL { url in router.handle(url: url) }
        // Hoisted above `calendarContent` and independent of `navigation.mode`
        // on purpose (Feature 2 DW-F2.5): a `calenminder://` deep link must
        // land on event/task detail no matter which Year/Month/Day mode is
        // currently showing underneath, exactly as it did before Feature 2.
        .sheet(isPresented: Binding(
            get: { router.route != nil },
            set: { isPresented in if !isPresented { router.dismiss() } }
        )) {
            routeContent
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        switch navigation.mode {
        case .year:
            YearView(viewModel: yearViewModel, navigation: navigation, agenda: agenda)
                .accessibilityIdentifier("root-year")
        case .month:
            MonthView(viewModel: monthViewModel, navigation: navigation, agenda: agenda)
                .accessibilityIdentifier("root-month")
        case .day:
            DayContainerView(agenda: agenda, navigation: navigation)
                .accessibilityIdentifier("root-agenda")
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

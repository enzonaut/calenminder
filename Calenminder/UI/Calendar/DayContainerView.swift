import SwiftUI
import CalenminderKit

/// Day mode: the week strip pinned above the existing single-day agenda,
/// which remains the detail surface unchanged (no hour-grid). `AgendaView`
/// keeps owning its own `NavigationStack`/toolbar; this view only adds the
/// strip above it and forwards `navigation` so the mode switcher can render
/// inside that same toolbar.
struct DayContainerView: View {
    @ObservedObject var agenda: AgendaViewModel
    @ObservedObject var navigation: CalendarNavigationViewModel

    var body: some View {
        VStack(spacing: 0) {
            WeekStripView(agenda: agenda)
            Divider()
            AgendaView(viewModel: agenda, navigation: navigation)
        }
        .accessibilityIdentifier("day-container")
    }
}

import SwiftUI
import CalenminderKit

/// The Year/Month/Day toolbar switcher, shared by all three calendar
/// screens. Anchors a switcher jump to `agenda.day` (the day the shared
/// `AgendaViewModel` last displayed) rather than to whatever year/month
/// happens to be on screen - matches Apple Calendar's own toolbar behavior,
/// where switching view level jumps to the current contextual day/month/year,
/// not to wherever Year/Month paging left off.
struct CalendarModeSwitcher: View {
    @ObservedObject var navigation: CalendarNavigationViewModel
    @ObservedObject var agenda: AgendaViewModel

    private enum Selection: Hashable { case year, month, day }

    var body: some View {
        Picker("Calendar View", selection: Binding(
            get: { selectionForCurrentMode },
            set: { select($0) }
        )) {
            Text("Year").tag(Selection.year)
            Text("Month").tag(Selection.month)
            Text("Day").tag(Selection.day)
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("calendar-mode-switcher")
    }

    private var selectionForCurrentMode: Selection {
        switch navigation.mode {
        case .year: return .year
        case .month: return .month
        case .day: return .day
        }
    }

    private func select(_ selection: Selection) {
        switch selection {
        case .year: navigation.showYear(agenda.day.year)
        case .month: navigation.showMonth(MonthStamp(containing: agenda.day))
        case .day: navigation.showDay()
        }
    }
}

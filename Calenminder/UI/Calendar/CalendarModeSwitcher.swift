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
        // Deliberately NOT `.fixedSize()`. As the `.principal` toolbar item,
        // this switcher is centered in the *full* nav-bar width; a fixed
        // intrinsic width (~186pt for "Year/Month/Day") cannot compress, so
        // whenever the leading `ToolbarItemGroup` is wider than the trailing
        // one - e.g. Day view drilled down, where leading carries back +
        // "Today" against trailing's two icon buttons - the centered switcher
        // slid sideways and overlapped the trailing buttons (confirmed on both
        // regular and compact widths; see `test_DW_B2_2_*` in
        // `CalendarToolbarLayoutUITests`). Letting it size to the available
        // middle zone keeps every reachable toolbar state overlap-free; it
        // shows full labels in every common state and only compresses in the
        // single most crowded reachable state, which is standard segmented-
        // control behavior under space pressure, not a broken layout.
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

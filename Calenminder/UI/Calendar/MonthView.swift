import SwiftUI
import CalenminderKit

/// Classic month grid: locale first-weekday, today highlighted, a dot for
/// days with visible events and a small incomplete-task count. Tapping a day
/// moves the shared `AgendaViewModel` to it and drills into Day view.
///
/// Feature 5: the grid area is a 3-tag `TabView(.page)` (previous month /
/// current month / next month - see `PageWindow`), so it pages by swipe in
/// addition to the two toolbar chevrons, which stay exactly where they were
/// and call exactly the same `MonthViewModel` methods they always did.
/// `previousViewModel`/`nextViewModel` are prefetching sibling view models
/// (`MonthViewModel.sibling(for:)`), rebuilt and reloaded whenever `viewModel
/// .month` changes - which happens identically whether that change came from
/// a chevron tap or a swipe settling, so chevron and swipe can never drift
/// out of sync. See the Feature 5 discovery doc's "Month view" design
/// decision for why prefetching (not a synchronous "adopt" swap) was chosen.
struct MonthView: View {
    @ObservedObject var viewModel: MonthViewModel
    @ObservedObject var navigation: CalendarNavigationViewModel
    @ObservedObject var agenda: AgendaViewModel

    @State private var previousViewModel: MonthViewModel
    @State private var nextViewModel: MonthViewModel
    @State private var pageSelection = PageWindow.centerIndex

    private var calendar: Calendar { .current }

    /// 6 rows (the maximum any Gregorian month ever needs) x `MonthDayCell`'s
    /// own 48pt `minHeight`, so a 4-row month and a 6-row month occupy the
    /// same on-screen height and neither the title nor the toolbar visibly
    /// shifts when paging between them.
    private static let pagerHeight: CGFloat = 6 * 48

    init(viewModel: MonthViewModel, navigation: CalendarNavigationViewModel, agenda: AgendaViewModel) {
        self.viewModel = viewModel
        self.navigation = navigation
        self.agenda = agenda
        _previousViewModel = State(initialValue: viewModel.sibling(for: viewModel.month.adding(months: -1, in: .current)))
        _nextViewModel = State(initialValue: viewModel.sibling(for: viewModel.month.adding(months: 1, in: .current)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekdayHeader
                TabView(selection: $pageSelection) {
                    MonthGridView(viewModel: previousViewModel, onSelectDay: selectDay).tag(0)
                    MonthGridView(viewModel: viewModel, onSelectDay: selectDay).tag(1)
                    MonthGridView(viewModel: nextViewModel, onSelectDay: selectDay).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: Self.pagerHeight)
                .accessibilityIdentifier("month-grid-pager")
                .onChange(of: pageSelection) { _, newValue in
                    handleSwipeSettle(newValue)
                }
                Spacer(minLength: 0)
            }
            .navigationTitle(monthTitle)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if navigation.parentMode != nil {
                        Button { navigation.back() } label: { Image(systemName: "chevron.backward") }
                            .accessibilityIdentifier("month-back")
                    }
                    Button { viewModel.goToPreviousMonth() } label: { Image(systemName: "chevron.left") }
                        .accessibilityIdentifier("month-previous")
                    Button { viewModel.goToNextMonth() } label: { Image(systemName: "chevron.right") }
                        .accessibilityIdentifier("month-next")
                }
                ToolbarItem(placement: .principal) {
                    CalendarModeSwitcher(navigation: navigation, agenda: agenda)
                }
            }
            .overlay {
                if viewModel.isLoading && viewModel.summaries.isEmpty {
                    ProgressView().accessibilityIdentifier("month-loading")
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task { await viewModel.load() }
        .task { await previousViewModel.load() }
        .task { await nextViewModel.load() }
        .onChange(of: viewModel.month) { _, _ in rebuildWindow() }
        .accessibilityIdentifier("month-view")
    }

    private func selectDay(_ day: DayStamp?) {
        guard let day else { return }
        agenda.goToDay(day)
        navigation.selectDay()
    }

    /// Non-zero `PageWindow` direction calls the exact same
    /// `goToPreviousMonth()`/`goToNextMonth()` the toolbar chevrons call,
    /// then recenters the pager. `rebuildWindow()` (triggered by the
    /// resulting `viewModel.month` change, via `.onChange` above) is what
    /// actually refreshes `previousViewModel`/`nextViewModel` around the new
    /// center - not this method - so chevron taps rebuild the window exactly
    /// the same way swipes do.
    private func handleSwipeSettle(_ selection: Int) {
        let direction = PageWindow.direction(forSelection: selection)
        guard direction != 0 else { return }
        if direction > 0 {
            viewModel.goToNextMonth()
        } else {
            viewModel.goToPreviousMonth()
        }
        pageSelection = PageWindow.centerIndex
    }

    /// Rebuilds `previousViewModel`/`nextViewModel` around the new center and
    /// starts an unawaited prefetch load for each - the "prefetch" mitigation
    /// for the blank-indicator flash called out in the Feature 5 plan. Runs
    /// once per actual month change, regardless of whether that change came
    /// from a chevron tap or a swipe settling.
    private func rebuildWindow() {
        previousViewModel = viewModel.sibling(for: viewModel.month.adding(months: -1, in: calendar))
        nextViewModel = viewModel.sibling(for: viewModel.month.adding(months: 1, in: calendar))
        Task { await previousViewModel.load() }
        Task { await nextViewModel.load() }
    }

    private var weekdayHeader: some View {
        let symbols = orderedWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    /// `calendar.veryShortWeekdaySymbols` is always Sunday-first regardless of
    /// `firstWeekday`; rotate it to match so the header lines up with the grid.
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var monthTitle: String {
        let symbols = calendar.monthSymbols
        let name = symbols.indices.contains(viewModel.month.month - 1) ? symbols[viewModel.month.month - 1] : "\(viewModel.month.month)"
        return "\(name) \(viewModel.month.year)"
    }
}

/// The grid renderer for a single month page - a plain `VStack` of `HStack`
/// rows, not `LazyVGrid` (see the forbidden-pattern note in
/// `docs/code-standards.md`: a `LazyVGrid` placed directly in a
/// non-scrolling container only lays out its first row). Parameterized by
/// whichever `MonthViewModel` is showing on a given `TabView` page (current/
/// previous/next), so all three of `MonthView`'s pages share one
/// implementation.
private struct MonthGridView: View {
    @ObservedObject var viewModel: MonthViewModel
    let onSelectDay: (DayStamp?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.grid.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                        MonthDayCell(
                            day: day,
                            isToday: day == viewModel.today,
                            summary: day.flatMap { viewModel.summaries[$0] }
                        )
                        .onTapGesture { onSelectDay(day) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct MonthDayCell: View {
    let day: DayStamp?
    let isToday: Bool
    let summary: DaySummary?

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isToday {
                    Circle().fill(Color.accentColor)
                }
                if let day {
                    Text("\(day.day)")
                        .font(.body)
                        .foregroundStyle(isToday ? .white : .primary)
                }
            }
            .frame(width: 30, height: 30)

            HStack(spacing: 3) {
                if summary?.hasEvents == true {
                    Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                        .accessibilityIdentifier("month-day-event-dot")
                }
                if let count = summary?.incompleteTaskCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("month-day-task-count")
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityIdentifier(day.map { "month-day-\($0.year)-\($0.month)-\($0.day)" } ?? "month-day-blank")
    }
}

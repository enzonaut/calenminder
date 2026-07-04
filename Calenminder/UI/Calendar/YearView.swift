import SwiftUI
import CalenminderKit

/// 12 mini-month grids for the displayed year, Apple Calendar's year-view
/// style: dates only, no per-day indicators (Year view fetches nothing
/// per-day - see `YearViewModel`). Tapping a month drills into Month view;
/// left/right toolbar buttons page between years.
///
/// Feature 5: the whole scrollable grid is a 3-tag `TabView(.page)` (previous
/// year / current year / next year - see `PageWindow`), so it pages by swipe
/// in addition to the two toolbar chevrons, which stay exactly where they
/// were. `YearViewModel` does no I/O at all (by design - see its own header
/// comment), so unlike Month's window, neighbor pages need no prefetching:
/// they are built inline from a throwaway `YearViewModel` for `year ± 1`.
struct YearView: View {
    @ObservedObject var viewModel: YearViewModel
    @ObservedObject var navigation: CalendarNavigationViewModel
    @ObservedObject var agenda: AgendaViewModel

    @State private var pageSelection = PageWindow.centerIndex

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            TabView(selection: $pageSelection) {
                yearGrid(for: viewModel.year - 1).tag(0)
                yearGrid(for: viewModel.year).tag(1)
                yearGrid(for: viewModel.year + 1).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("year-pager")
            .onChange(of: pageSelection) { _, newValue in
                handleSwipeSettle(newValue)
            }
            .navigationTitle(String(viewModel.year))
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button { viewModel.goToPreviousYear() } label: { Image(systemName: "chevron.left") }
                        .accessibilityIdentifier("year-previous")
                    Button { viewModel.goToNextYear() } label: { Image(systemName: "chevron.right") }
                        .accessibilityIdentifier("year-next")
                }
                ToolbarItem(placement: .principal) {
                    CalendarModeSwitcher(navigation: navigation, agenda: agenda)
                }
            }
        }
    }

    /// A single year's page - the same `monthGrids`/today-highlight rendering
    /// `YearViewModel` already provided, just addressed by an explicit `year`
    /// so it can be built for `viewModel.year - 1`/`+ 1` without touching the
    /// externally-owned `viewModel`.
    private func yearGrid(for year: Int) -> some View {
        let entries = viewModel.sibling(for: year).monthGrids
        let today = viewModel.today
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(entries, id: \.month) { entry in
                    MiniMonthView(month: entry.month, grid: entry.grid, today: today)
                        .contentShape(Rectangle())
                        .onTapGesture { navigation.selectMonth(entry.month) }
                        .accessibilityIdentifier("year-month-\(entry.month.year)-\(entry.month.month)")
                }
            }
            .padding()
        }
        .accessibilityIdentifier("year-grid-\(year)")
    }

    /// Non-zero `PageWindow` direction calls the exact same
    /// `goToPreviousYear()`/`goToNextYear()` the toolbar chevrons call, then
    /// recenters the pager - identical shape to `MonthView.handleSwipeSettle`.
    private func handleSwipeSettle(_ selection: Int) {
        let direction = PageWindow.direction(forSelection: selection)
        guard direction != 0 else { return }
        if direction > 0 {
            viewModel.goToNextYear()
        } else {
            viewModel.goToPreviousYear()
        }
        pageSelection = PageWindow.centerIndex
    }
}

private struct MiniMonthView: View {
    let month: MonthStamp
    let grid: [[DayStamp?]]
    let today: DayStamp

    var body: some View {
        VStack(spacing: 6) {
            Text(monthTitle)
                .font(.caption.weight(.semibold))
            VStack(spacing: 2) {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 2) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                            dayCell(day)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var monthTitle: String {
        Calendar.current.shortMonthSymbols[safe: month.month - 1] ?? "\(month.month)"
    }

    @ViewBuilder
    private func dayCell(_ day: DayStamp?) -> some View {
        ZStack {
            if day == today {
                Circle().fill(Color.accentColor)
            }
            if let day {
                Text("\(day.day)")
                    .font(.system(size: 9))
                    .foregroundStyle(day == today ? .white : .primary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 14)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

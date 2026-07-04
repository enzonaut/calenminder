import SwiftUI
import CalenminderKit

/// 12 mini-month grids for the displayed year, Apple Calendar's year-view
/// style: dates only, no per-day indicators (Year view fetches nothing
/// per-day - see `YearViewModel`). Tapping a month drills into Month view;
/// left/right toolbar buttons page between years.
struct YearView: View {
    @ObservedObject var viewModel: YearViewModel
    @ObservedObject var navigation: CalendarNavigationViewModel
    @ObservedObject var agenda: AgendaViewModel

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(viewModel.monthGrids, id: \.month) { entry in
                        MiniMonthView(month: entry.month, grid: entry.grid, today: viewModel.today)
                            .contentShape(Rectangle())
                            .onTapGesture { navigation.selectMonth(entry.month) }
                            .accessibilityIdentifier("year-month-\(entry.month.year)-\(entry.month.month)")
                    }
                }
                .padding()
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

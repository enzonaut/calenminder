import SwiftUI
import CalenminderKit

/// Classic month grid: locale first-weekday, today highlighted, a dot for
/// days with visible events and a small incomplete-task count. Tapping a day
/// moves the shared `AgendaViewModel` to it and drills into Day view.
struct MonthView: View {
    @ObservedObject var viewModel: MonthViewModel
    @ObservedObject var navigation: CalendarNavigationViewModel
    @ObservedObject var agenda: AgendaViewModel

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekdayHeader
                monthGrid
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
        .accessibilityIdentifier("month-view")
    }

    private func selectDay(_ day: DayStamp?) {
        guard let day else { return }
        agenda.goToDay(day)
        navigation.selectDay()
    }

    /// Plain `VStack` of `HStack` rows, not `LazyVGrid`: a `LazyVGrid` placed
    /// directly in a non-scrolling `VStack` only lays out its first row (the
    /// rest silently collapses to zero height - a real, confirmed bug, not a
    /// hypothetical one; see the Feature 4 UI bug-fix discovery doc). Every
    /// week (4-6 rows) must always be visible with no scrolling, matching
    /// `YearView`'s `MiniMonthView`, which renders this exact same
    /// row-of-`DayStamp?` shape correctly using this same pattern.
    private var monthGrid: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.grid.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                        MonthDayCell(
                            day: day,
                            isToday: day == viewModel.today,
                            summary: day.flatMap { viewModel.summaries[$0] }
                        )
                        .onTapGesture { selectDay(day) }
                    }
                }
            }
        }
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

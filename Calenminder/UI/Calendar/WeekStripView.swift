import SwiftUI
import CalenminderKit

/// A 7-day week strip above Day view's existing agenda list. Derives
/// everything it shows from the shared `AgendaViewModel.day` (via
/// `WeekLayout`, a pure function) rather than holding its own selected-day
/// state - so `goToToday()`, midnight rollover, and any other way
/// `AgendaViewModel.day` changes automatically re-center the strip, with
/// nothing to fall out of sync (see the Feature 2 design doc).
///
/// Feature 5: the 7-day row itself is a 3-tag `TabView(.page)` (previous
/// week / current week / next week - see `PageWindow`), so it pages by swipe
/// in addition to the two chevron buttons, which stay right where they were.
/// No I/O and no per-page async load happens here (unlike Month's swipe
/// window), so unlike Day view there is no `List`/gesture-conflict risk to
/// design around - `TabView(.page)` is used directly, per the Feature 5
/// discovery doc.
struct WeekStripView: View {
    @ObservedObject var agenda: AgendaViewModel
    @State private var pageSelection = PageWindow.centerIndex

    private var calendar: Calendar { .current }
    private var today: DayStamp { DayStamp(date: Date(), calendar: calendar) }

    /// [previous week's days, current week's days, next week's days] - each
    /// built from `WeekLayout.shiftedDay`, the same pure function the
    /// chevron buttons and swipe-settle both call.
    private var weekWindow: [[DayStamp]] {
        [-1, 0, 1].map { weekOffset in
            let anchor = WeekLayout.shiftedDay(from: agenda.day, byWeeks: weekOffset, calendar: calendar)
            return WeekLayout.days(containing: anchor, calendar: calendar)
        }
    }

    var body: some View {
        // The chevrons are an `.overlay`, not `HStack` siblings of the
        // `TabView`: nesting `TabView(.page)` inside an `HStack` alongside
        // fixed-size sibling views is a real, confirmed layout bug (not
        // hypothetical) - the `TabView` claims effectively all available
        // width, squeezing the chevron `Button`s down to zero size (absent
        // from the rendered UI and the accessibility tree entirely, not just
        // visually cramped). An overlay does not participate in that width
        // negotiation, so the `TabView` gets the full row width and the
        // chevrons float on top at each edge instead - `weekRow`'s own
        // horizontal padding keeps the day cells clear of them.
        TabView(selection: $pageSelection) {
            ForEach(Array(weekWindow.enumerated()), id: \.offset) { index, days in
                weekRow(days).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 52)
        .accessibilityIdentifier("week-strip-pager")
        .onChange(of: pageSelection) { _, newValue in
            handleSwipeSettle(newValue)
        }
        .overlay(alignment: .leading) {
            Button { pageWeek(by: -1) } label: { Image(systemName: "chevron.left") }
                .accessibilityIdentifier("week-strip-previous")
        }
        .overlay(alignment: .trailing) {
            Button { pageWeek(by: 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityIdentifier("week-strip-next")
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("week-strip")
    }

    private func weekRow(_ days: [DayStamp]) -> some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                WeekStripDayView(day: day, isSelected: day == agenda.day, isToday: day == today)
                    .contentShape(Rectangle())
                    .onTapGesture { agenda.goToDay(day) }
                    .accessibilityIdentifier("week-strip-day-\(day.year)-\(day.month)-\(day.day)")
            }
        }
        // Leaves the leading/trailing edges clear of the overlaid chevrons.
        .padding(.horizontal, 24)
    }

    /// Mirrors `MonthView`/`YearView`'s `handleSwipeSettle`: a non-zero
    /// `PageWindow` direction calls the exact same `pageWeek(by:)` the
    /// chevron buttons call, then recenters the pager. Because `weekWindow`
    /// is recomputed from `agenda.day` (the single source of truth) rather
    /// than from any locally-held state, the recentered tag 1 already shows
    /// the same week the user just swiped to - no visible jump.
    private func handleSwipeSettle(_ selection: Int) {
        let direction = PageWindow.direction(forSelection: selection)
        guard direction != 0 else { return }
        pageWeek(by: direction)
        pageSelection = PageWindow.centerIndex
    }

    private func pageWeek(by weeks: Int) {
        agenda.goToDay(WeekLayout.shiftedDay(from: agenda.day, byWeeks: weeks, calendar: calendar))
    }
}

private struct WeekStripDayView: View {
    let day: DayStamp
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(weekdayLetter)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ZStack {
                if isSelected {
                    Circle().fill(Color.accentColor)
                } else if isToday {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 1)
                }
                Text("\(day.day)")
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(width: 28, height: 28)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekdayLetter: String {
        guard let date = day.startOfDay(in: .current) else { return "" }
        return date.formatted(.dateTime.weekday(.narrow))
    }
}

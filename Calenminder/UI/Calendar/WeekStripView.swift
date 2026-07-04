import SwiftUI
import CalenminderKit

/// A 7-day week strip above Day view's existing agenda list. Derives
/// everything it shows from the shared `AgendaViewModel.day` (via
/// `WeekLayout`, a pure function) rather than holding its own selected-day
/// state - so `goToToday()`, midnight rollover, and any other way
/// `AgendaViewModel.day` changes automatically re-center the strip, with
/// nothing to fall out of sync (see the Feature 2 design doc).
struct WeekStripView: View {
    @ObservedObject var agenda: AgendaViewModel

    private var calendar: Calendar { .current }
    private var weekDays: [DayStamp] { WeekLayout.days(containing: agenda.day, calendar: calendar) }
    private var today: DayStamp { DayStamp(date: Date(), calendar: calendar) }

    var body: some View {
        HStack(spacing: 0) {
            Button { pageWeek(by: -1) } label: { Image(systemName: "chevron.left") }
                .accessibilityIdentifier("week-strip-previous")

            ForEach(weekDays, id: \.self) { day in
                WeekStripDayView(day: day, isSelected: day == agenda.day, isToday: day == today)
                    .contentShape(Rectangle())
                    .onTapGesture { agenda.goToDay(day) }
                    .accessibilityIdentifier("week-strip-day-\(day.year)-\(day.month)-\(day.day)")
            }

            Button { pageWeek(by: 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityIdentifier("week-strip-next")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityIdentifier("week-strip")
    }

    private func pageWeek(by weeks: Int) {
        guard
            let start = agenda.day.startOfDay(in: calendar),
            let shifted = calendar.date(byAdding: .day, value: weeks * 7, to: start)
        else { return }
        agenda.goToDay(DayStamp(date: shifted, calendar: calendar))
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

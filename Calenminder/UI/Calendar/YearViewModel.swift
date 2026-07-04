import Foundation
import CalenminderKit

/// Year view's view model. Deliberately holds no `AgendaService` reference at
/// all - per the Feature 2 spec, Year view fetches nothing per-day, so there
/// is no I/O here to model: `monthGrids` is a pure computed property over
/// `year` and `calendar`.
@MainActor
final class YearViewModel: ObservableObject {
    @Published private(set) var year: Int

    private let calendar: Calendar
    private let now: () -> Date

    init(year: Int? = nil, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
        self.year = year ?? calendar.component(.year, from: now())
    }

    /// The 12 months of `year`, each paired with its blank-padded grid.
    var monthGrids: [(month: MonthStamp, grid: [[DayStamp?]])] {
        (1...12).map { monthNumber in
            let month = MonthStamp(year: year, month: monthNumber)
            return (month, MonthGrid.rows(for: month, calendar: calendar))
        }
    }

    /// Today's `DayStamp`, for the "highlight today" rule - only meaningful
    /// when `year` is the year today falls in; a month grid outside that year
    /// simply never matches it.
    var today: DayStamp {
        DayStamp(date: now(), calendar: calendar)
    }

    func goToPreviousYear() {
        year -= 1
    }

    func goToNextYear() {
        year += 1
    }
}

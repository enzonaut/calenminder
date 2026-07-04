import Foundation
import CalenminderKit

/// Month view's view model. Fetches exactly one `monthSummary` per displayed
/// month (never per-day) via the pinned `AgendaService` seam; the grid shape
/// itself (`MonthGrid.rows`) is pure and recomputed with no I/O whenever
/// `month` changes.
@MainActor
final class MonthViewModel: ObservableObject {
    @Published private(set) var month: MonthStamp
    @Published private(set) var grid: [[DayStamp?]] = []
    @Published private(set) var summaries: [DayStamp: DaySummary] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let agendaService: AgendaService
    private let calendar: Calendar
    private let now: () -> Date

    init(
        agendaService: AgendaService,
        month: MonthStamp? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.agendaService = agendaService
        self.calendar = calendar
        self.now = now
        let resolvedMonth = month ?? MonthStamp(containing: DayStamp(date: now(), calendar: calendar))
        self.month = resolvedMonth
        self.grid = MonthGrid.rows(for: resolvedMonth, calendar: calendar)
    }

    var today: DayStamp {
        DayStamp(date: now(), calendar: calendar)
    }

    func load() async {
        grid = MonthGrid.rows(for: month, calendar: calendar)
        guard let window = DayWindow(month: month, calendar: calendar) else {
            errorMessage = "Something went wrong determining that month's dates."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            summaries = try await agendaService.monthSummary(for: window, filter: .agenda)
            errorMessage = nil
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    func goToPreviousMonth() {
        shiftMonth(by: -1)
    }

    func goToNextMonth() {
        shiftMonth(by: 1)
    }

    func goTo(_ newMonth: MonthStamp) {
        guard newMonth != month else { return }
        month = newMonth
        Task { await load() }
    }

    private func shiftMonth(by value: Int) {
        month = month.adding(months: value, in: calendar)
        Task { await load() }
    }

    /// Builds a sibling view model for a different month, reusing this
    /// instance's own `agendaService`/`calendar`/clock - `agendaService` stays
    /// `private`, so `MonthView`'s swipe-paging window (see the Feature 5
    /// discovery doc) can prefetch adjacent months without needing its own
    /// reference to it. The returned instance has its `grid` already computed
    /// (synchronous, no I/O - see `init`) but has not been `load()`-ed yet;
    /// that is the caller's responsibility, matching every other
    /// `MonthViewModel` construction site in this codebase.
    func sibling(for month: MonthStamp) -> MonthViewModel {
        MonthViewModel(agendaService: agendaService, month: month, calendar: calendar, now: now)
    }
}

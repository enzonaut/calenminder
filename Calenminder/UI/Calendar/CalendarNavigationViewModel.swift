import Foundation
import CalenminderKit

/// Which top-level calendar screen is showing. A flat switch, not a
/// `NavigationStack` push hierarchy - `AgendaView` (Day) already owns its own
/// `NavigationStack` for its own toolbar, so nesting Day as a *pushed
/// destination* inside another stack would mean nested `NavigationStack`s (a
/// known SwiftUI footgun) for no behavioral gain. See the Feature 2 design
/// doc's navigation design decision.
enum CalendarViewMode: Equatable {
    case year(Int)
    case month(MonthStamp)
    case day
}

/// Owns which `CalendarViewMode` is showing and one level of "back" - a
/// single remembered parent, not a full history stack. Deliberately no I/O:
/// pure, synchronous, `@MainActor` state, unit-testable without SwiftUI or
/// `AgendaService`.
///
/// Drill-down (`selectMonth`/`selectDay`) remembers where it came from so
/// `back()` can return to it. A direct switcher jump (`showYear`/`showMonth`/
/// `showDay`) is not a drill - it clears any remembered parent, matching
/// Apple Calendar's own UX where the mode switcher never builds a back-stack.
@MainActor
final class CalendarNavigationViewModel: ObservableObject {
    @Published private(set) var mode: CalendarViewMode
    @Published private(set) var parentMode: CalendarViewMode?

    init(mode: CalendarViewMode = .day) {
        self.mode = mode
        self.parentMode = nil
    }

    /// Year view -> Month view, remembering Year as the back-target.
    func selectMonth(_ month: MonthStamp) {
        parentMode = mode
        mode = .month(month)
    }

    /// Month view (or the week strip) -> Day view, remembering the mode drilled
    /// from as the back-target. `agenda.goToDay(day)` is the caller's job (this
    /// view model has no `AgendaViewModel` reference by design - navigation
    /// mode and the displayed day are separate concerns).
    func selectDay() {
        parentMode = mode
        mode = .day
    }

    /// One-level undo of the most recent drill-down; a no-op if the current
    /// mode was reached via a direct switcher jump (nothing to go back to).
    func back() {
        guard let parentMode else { return }
        mode = parentMode
        self.parentMode = nil
    }

    func showYear(_ year: Int) {
        mode = .year(year)
        parentMode = nil
    }

    func showMonth(_ month: MonthStamp) {
        mode = .month(month)
        parentMode = nil
    }

    func showDay() {
        mode = .day
        parentMode = nil
    }
}

import Foundation

/// Feature 3: the icon-badge orchestrator - "how many incomplete tasks does
/// the user have right now, and is the icon allowed to show that." Both the
/// app and the widget-intent process build their own instance of this exact
/// type over the exact same real `AgendaService`/`SystemBadgeSetter`, the
/// same way both already build their own `AgendaService` (see
/// `AgendaService`'s own doc comment on being "equally correct for a
/// long-lived app process and a widget process that runs once per timeline
/// entry" - `BadgeUpdater` carries no more state than that, so the same
/// reasoning applies unchanged).
///
/// `updateBadge()` never throws: a store failure (e.g. Reminders access
/// denied) degrades to a badge of 0 rather than propagating, and
/// authorization is asked for (or re-asked, harmlessly, once already
/// determined) on every single call - see `BadgeSetting`'s doc for why that
/// is what makes "re-evaluated on later foregrounds" (DW-F3.3) true with no
/// extra bookkeeping.
///
/// Lifecycle awareness (*when* to call this) deliberately stays out of this
/// type and out of `CalenminderKit` entirely - the app layer decides that
/// (`AgendaViewModel.handleForeground()`/`handleBackground()`, task-mutation
/// call sites, `BadgeRefreshScheduler`) and the widget layer decides it too
/// (`CompleteTaskIntent`). This mirrors the Phase 4 design doc's existing
/// split for `AgendaService.reloadWidgets()`.
public final class BadgeUpdater {
    private let agendaService: AgendaService
    private let badgeSetting: BadgeSetting
    private let calendar: Calendar
    private let now: () -> Date

    public init(
        agendaService: AgendaService,
        badgeSetting: BadgeSetting = SystemBadgeSetter(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.agendaService = agendaService
        self.badgeSetting = badgeSetting
        self.calendar = calendar
        self.now = now
    }

    // PSEUDOCODE: updateBadge()
    //   Ask badgeSetting to request authorization if not yet determined
    //   (never prompts twice; harmless no-op once granted or denied).
    //   Compute today's DayStamp from the injected clock/calendar.
    //   Ask agendaService for today's badge count; if that throws (e.g. a
    //   store access failure), treat the count as 0 rather than
    //   propagating - a failed count is exactly the "feature silently off"
    //   case DW-F3.3 asks for, not an error to surface.
    //   Hand the resulting count to badgeSetting to actually set the icon
    //   badge (0 clears it; iOS truncates anything over its own display
    //   limit natively, so the real number is always passed through as-is).

    /// Recomputes and applies the icon badge for "today." Never throws.
    public func updateBadge() async {
        await badgeSetting.requestAuthorizationIfNeeded()
        let day = DayStamp(date: now(), calendar: calendar)
        let count = (try? await agendaService.badgeCount(asOf: day)) ?? 0
        await badgeSetting.applyBadgeCount(count)
    }
}

import EventKit

/// Typed failures for the EventKit-backed stores. Expected failures are typed
/// and carry their recovery route (per `docs/code-standards.md` Error
/// Handling) -- callers pattern-match these to drive UI, they never see a
/// bare `Error` from a store call.
///
/// Public: this crosses the `Store` -> caller (Phase 4/5) throw boundary, so
/// unlike the provider seam beneath it, this type must be visible outside
/// `CalenminderKit`.
public enum CalendarStoreError: Error {
    /// No usable access to this entity type (denied, restricted, or the user
    /// declined the access prompt). Recovery: deep-link to Settings and show
    /// a placeholder until access is granted.
    case accessDenied(EKEntityType)
    /// Access is write-only (events can be created but the store cannot be
    /// read/queried). Recovery: explain that full access is needed and offer
    /// the settings deep link again.
    case writeOnlyAccess
    /// The item this call targeted is gone from the system store (deleted by
    /// another client, moved, or never existed). Detected via
    /// `EKEventStore.refresh() == false` or a failed re-resolution by
    /// `calendarItemExternalIdentifier`. Recovery: dismiss any open editor
    /// and refetch the window.
    case itemDeletedUnderneath
    /// EventKit's `save`/`remove` threw. Recovery: surface the underlying
    /// message and let the caller retry.
    case saveFailed(underlying: Error)
}

import Foundation
import EventKit

/// The testable seam beneath `EventKitEventStore`. Deliberately narrower than
/// `EKEventStore`'s full surface -- only the operations `EventKitEventStore`
/// actually makes, expressed in the terms it needs (dates, `RawEventRecord`),
/// never a raw `NSPredicate` or `EKEvent`. This is what lets
/// `FixtureCalendarProvider` implement it with a plain in-memory array
/// instead of faking EventKit's (non-generically-evaluable) predicates or its
/// store-bound event objects.
///
/// Internal, not public: this is an implementation detail of `Store`. Only
/// `EventKitEventStore` (a `EventStoring` conformance) and `CalendarStoreError`
/// (which crosses the public throw boundary) are public API of this module.
/// `CalenminderTests` reaches this via `@testable import CalenminderKit`.
protocol EventProviding: AnyObject {
    /// Republishes `.EKEventStoreChanged` (or the fixture's simulated
    /// equivalent). One independent stream per provider instance -- see
    /// the Phase 3 design doc for why stores never share one.
    var changes: AsyncStream<Void> { get }

    func requestFullAccessToEvents() async throws -> Bool
    func eventAuthorizationStatus() -> EKAuthorizationStatus

    /// All event occurrences overlapping `[start, end)`, across every
    /// calendar. Membership/participation filtering happens above this seam
    /// (in `Domain`), so this returns candidates, not a filtered result.
    func fetchEvents(start: Date, end: Date) -> [RawEventRecord]

    func createEvent(_ draft: RawEventDraft) throws -> RawEventRecord

    /// Applies `draft`'s fields to the occurrence identified by
    /// `(externalIdentifier, occurrenceDate)`. Throws `.itemDeletedUnderneath`
    /// if that occurrence no longer resolves.
    func updateEvent(externalIdentifier: String, occurrenceDate: Date, draft: RawEventDraft, span: EKSpan) throws -> RawEventRecord

    func deleteEvent(externalIdentifier: String, occurrenceDate: Date, span: EKSpan) throws

    /// Best-effort refresh of remote sources; a no-op for a fixture.
    func refreshSourcesIfNecessary()
}

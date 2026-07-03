import Foundation

/// Internal failure signal from the provider seam. `EventKitEventStore`/
/// `ReminderTaskStore` translate this into the public `CalendarStoreError`
/// -- the seam itself stays free of the public error type so
/// `FixtureCalendarProvider` never needs to know how its failures get
/// presented to callers.
enum ProviderError: Error {
    /// The item this call targeted does not resolve any more (deleted
    /// underneath, or never existed).
    case itemNotFound
    /// The underlying EventKit call threw.
    case underlying(Error)
}

import Foundation

/// A calendar (the container events belong to, e.g. "Home", "Work") as seen
/// by the visibility-toggle UI. Pure Domain value type - no `EKCalendar`
/// leaks through, same discipline as `Event`/`DayTask`.
///
/// Color is carried as RGB components rather than a platform color type:
/// `Domain` (and `EventCalendarInfo` lives there) must stay free of
/// UIKit/SwiftUI imports, so the UI layer converts these components to
/// `Color` itself.
public struct EventCalendarInfo: Equatable, Identifiable, Sendable {
    public let identifier: String
    public let title: String
    public let colorRed: Double
    public let colorGreen: Double
    public let colorBlue: Double
    /// Whether this calendar's events currently pass the user's visibility
    /// toggle. `true` is the default for a calendar the user has never
    /// explicitly hidden.
    public let isVisible: Bool

    public init(
        identifier: String,
        title: String,
        colorRed: Double,
        colorGreen: Double,
        colorBlue: Double,
        isVisible: Bool
    ) {
        self.identifier = identifier
        self.title = title
        self.colorRed = colorRed
        self.colorGreen = colorGreen
        self.colorBlue = colorBlue
        self.isVisible = isVisible
    }

    public var id: String { identifier }
}

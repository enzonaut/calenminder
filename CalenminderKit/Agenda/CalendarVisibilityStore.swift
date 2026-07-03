import Foundation

/// User preference: which event calendars are hidden from the agenda.
/// Deliberately stores the *hidden* set, not the visible set, so a calendar
/// nobody has ever touched (including one that did not exist yet when the
/// preference was last saved) defaults to visible.
public protocol CalendarVisibilityStoring: AnyObject {
    func isVisible(calendarIdentifier: String) -> Bool
    func setVisible(_ visible: Bool, calendarIdentifier: String)
}

/// `UserDefaults`-backed implementation. Uses the App Group suite so this
/// preference is readable by both the app and (from Phase 5) the widget
/// extension process, keeping the two surfaces' agendas consistent.
public final class CalendarVisibilityStore: CalendarVisibilityStoring {
    private static let key = "calendarVisibility.hiddenIdentifiers"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppGroup.sharedDefaults ?? .standard) {
        self.defaults = defaults
    }

    public func isVisible(calendarIdentifier: String) -> Bool {
        !hiddenIdentifiers.contains(calendarIdentifier)
    }

    public func setVisible(_ visible: Bool, calendarIdentifier: String) {
        var hidden = hiddenIdentifiers
        if visible {
            hidden.remove(calendarIdentifier)
        } else {
            hidden.insert(calendarIdentifier)
        }
        defaults.set(Array(hidden), forKey: Self.key)
    }

    private var hiddenIdentifiers: Set<String> {
        Set(defaults.stringArray(forKey: Self.key) ?? [])
    }
}

import Foundation

/// Constants for the Phase 1 platform spike: proving a widget-extension
/// `Button(intent:)` can mark an `EKReminder` complete.
///
/// This is throwaway scaffolding (Phase 1 scope is explicitly OUT: real
/// domain models/stores). It intentionally does NOT use the durable
/// `calendarItemExternalIdentifier` persistence pattern the real `Task`
/// domain type will use starting Phase 2/3 -- a dedicated-list + known-title
/// lookup is sufficient and simpler for code that gets deleted once the
/// spike's verdict is recorded.
public enum SpikeConfig {
    /// Dedicated Reminders list the app seeds and the widget's intent reads.
    public static let listName = "Calenminder Spike"

    /// Title of the single reminder the spike creates and completes.
    public static let reminderTitle = "Spike: tap to complete"
}

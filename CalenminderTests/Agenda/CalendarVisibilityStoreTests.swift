import Testing
import Foundation
@testable import CalenminderKit

struct CalendarVisibilityStoreTests {
    private func makeStore() -> CalendarVisibilityStore {
        let suiteName = "CalendarVisibilityStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return CalendarVisibilityStore(defaults: defaults)
    }

    @Test("A calendar never explicitly set defaults to visible")
    func unsetCalendarDefaultsVisible() {
        let store = makeStore()
        #expect(store.isVisible(calendarIdentifier: "unknown") == true)
    }

    @Test("Hiding a calendar persists through the same store instance")
    func hidingPersists() {
        let store = makeStore()
        store.setVisible(false, calendarIdentifier: "cal-1")
        #expect(store.isVisible(calendarIdentifier: "cal-1") == false)
        #expect(store.isVisible(calendarIdentifier: "cal-2") == true)
    }

    @Test("Re-showing a previously hidden calendar restores default visibility")
    func reshowingRestoresVisibility() {
        let store = makeStore()
        store.setVisible(false, calendarIdentifier: "cal-1")
        store.setVisible(true, calendarIdentifier: "cal-1")
        #expect(store.isVisible(calendarIdentifier: "cal-1") == true)
    }

    @Test("Visibility persists across two store instances sharing the same defaults suite")
    func persistsAcrossInstances() {
        let suiteName = "CalendarVisibilityStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        CalendarVisibilityStore(defaults: defaults).setVisible(false, calendarIdentifier: "cal-1")
        #expect(CalendarVisibilityStore(defaults: defaults).isVisible(calendarIdentifier: "cal-1") == false)
    }
}

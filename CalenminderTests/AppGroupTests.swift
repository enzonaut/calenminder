import Testing
@testable import CalenminderKit

/// Smoke coverage that the CalenminderTests target itself builds and runs
/// (DW-1.1) and that the shared App Group identifier the plan requires
/// ("shared App Group identifier constant exposed from the shared target")
/// is actually exposed and well-formed.
struct AppGroupTests {
    @Test("DW-1.1: AppGroup identifier is exposed from the shared target and non-empty")
    func test_DW_1_1_appGroupIdentifierIsExposed() {
        #expect(!AppGroup.identifier.isEmpty)
    }

    @Test("AppGroup identifier follows the group.<reverse-dns> convention")
    func appGroupIdentifierFollowsConvention() {
        #expect(AppGroup.identifier.hasPrefix("group."))
    }

    @Test("Spike config names are non-empty and distinct")
    func spikeConfigNamesAreDistinct() {
        #expect(!SpikeConfig.listName.isEmpty)
        #expect(!SpikeConfig.reminderTitle.isEmpty)
        #expect(SpikeConfig.listName != SpikeConfig.reminderTitle)
    }
}

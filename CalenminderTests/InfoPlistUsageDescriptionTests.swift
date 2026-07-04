import Testing
import Foundation

/// DW-1.3: both the app and widget Info.plists must carry
/// NSRemindersFullAccessUsageDescription and NSCalendarsFullAccessUsageDescription
/// with non-empty values (an empty description would pass App Review checks
/// for "key present" but fail to explain the request to the user).
///
/// Reads the committed Info.plist *source* files directly (via a
/// `#filePath`-relative path back to the repo root), rather than the
/// compiled app/widget bundles, because the test target does not embed
/// those bundles as resources. This is a static content check, matching
/// the plan's Test Plan T-1.2 ("static check asserts both Info.plists carry
/// the EventKit usage-description keys").
struct InfoPlistUsageDescriptionTests {
    private static let requiredKeys = [
        "NSRemindersFullAccessUsageDescription",
        "NSCalendarsFullAccessUsageDescription",
    ]

    private static var repoRoot: URL {
        // This file lives at <repoRoot>/CalenminderTests/InfoPlistUsageDescriptionTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CalenminderTests/
            .deletingLastPathComponent() // repo root
    }

    private static func loadPlist(at relativePath: String) throws -> [String: Any] {
        let url = repoRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            Issue.record("Could not parse plist at \(relativePath) as a dictionary")
            return [:]
        }
        return plist
    }

    @Test("DW-1.3: app Info.plist carries both EventKit usage-description keys")
    func test_DW_1_3_appInfoPlistHasUsageDescriptionKeys() throws {
        let plist = try Self.loadPlist(at: "Calenminder/Info.plist")
        for key in Self.requiredKeys {
            let value = plist[key] as? String
            #expect(value != nil, "app Info.plist is missing \(key)")
            #expect(!(value ?? "").isEmpty, "app Info.plist's \(key) must not be an empty string")
        }
    }

    @Test("DW-1.3: widget Info.plist carries both EventKit usage-description keys")
    func test_DW_1_3_widgetInfoPlistHasUsageDescriptionKeys() throws {
        let plist = try Self.loadPlist(at: "CalenminderWidget/Info.plist")
        for key in Self.requiredKeys {
            let value = plist[key] as? String
            #expect(value != nil, "widget Info.plist is missing \(key)")
            #expect(!(value ?? "").isEmpty, "widget Info.plist's \(key) must not be an empty string")
        }
    }

    @Test("widget Info.plist declares the widgetkit-extension point identifier")
    func widgetInfoPlistDeclaresExtensionPoint() throws {
        let plist = try Self.loadPlist(at: "CalenminderWidget/Info.plist")
        let extensionDict = plist["NSExtension"] as? [String: Any]
        #expect(extensionDict?["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension")
    }

    /// DW-F3.4: the app's Info.plist must list the exact identifier
    /// `BadgeRefreshScheduler` registers/submits under
    /// `BGTaskSchedulerPermittedIdentifiers` - a mismatch between this
    /// literal and `BadgeRefreshScheduler.taskIdentifier` fails
    /// registration/submission silently at runtime with no compile-time
    /// signal, which is exactly what this static check guards against.
    @Test("DW-F3.4: app Info.plist declares the badge-refresh BGTaskScheduler identifier")
    func test_DW_F3_4_appInfoPlistDeclaresBackgroundTaskIdentifier() throws {
        let plist = try Self.loadPlist(at: "Calenminder/Info.plist")
        let identifiers = plist["BGTaskSchedulerPermittedIdentifiers"] as? [String]
        #expect(identifiers?.contains("com.enzonaut.calenminder.badgeRefresh") == true)
    }
}

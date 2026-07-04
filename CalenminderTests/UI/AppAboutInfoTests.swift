import Testing
import Foundation
@testable import Calenminder

/// DW-AS.1: the About section's data model formats version/build text and
/// carries the fixed GitHub/privacy-policy links and privacy statement.
/// `AppAboutInfo` is a pure struct (see its header comment) so these tests
/// exercise the formatting logic directly rather than depending on
/// `Bundle.main`, which inside `CalenminderTests` resolves to the test
/// bundle, not the app's.
struct AppAboutInfoTests {
    @Test("DW-AS.1: versionLabel formats short version and build number together")
    func test_DW_AS_1_versionLabelFormatsBothFields() {
        let info = AppAboutInfo(shortVersion: "1.0", buildNumber: "1")

        #expect(info.versionLabel == "Version 1.0 (1)")
    }

    @Test("DW-AS.1: versionLabel falls back to 'unknown' for a missing short version")
    func test_DW_AS_1_versionLabelFallsBackForMissingShortVersion() {
        let info = AppAboutInfo(shortVersion: nil, buildNumber: "7")

        #expect(info.versionLabel == "Version unknown (7)")
    }

    @Test("DW-AS.1: versionLabel falls back to 'unknown' for a missing or empty build number")
    func test_DW_AS_1_versionLabelFallsBackForMissingOrEmptyBuild() {
        #expect(AppAboutInfo(shortVersion: "2.1", buildNumber: nil).versionLabel == "Version 2.1 (unknown)")
        #expect(AppAboutInfo(shortVersion: "2.1", buildNumber: "").versionLabel == "Version 2.1 (unknown)")
    }

    @Test("DW-AS.1: default privacy statement matches the required one-line claim")
    func test_DW_AS_1_defaultPrivacyStatement() {
        let info = AppAboutInfo(shortVersion: "1.0", buildNumber: "1")

        #expect(info.privacyStatement == "All data stays on your device - no servers, no analytics.")
    }

    @Test("DW-AS.1: default links point at the GitHub repo and the PRIVACY.md blob URL")
    func test_DW_AS_1_defaultLinks() {
        let info = AppAboutInfo(shortVersion: "1.0", buildNumber: "1")

        #expect(info.githubURL == URL(string: "https://github.com/enzonaut/calenminder")!)
        #expect(info.privacyPolicyURL == URL(string: "https://github.com/enzonaut/calenminder/blob/main/PRIVACY.md")!)
    }

    @Test("DW-AS.1: fromBundle(_:) reads CFBundleShortVersionString/CFBundleVersion from an arbitrary bundle")
    func test_DW_AS_1_fromBundleReadsInfoDictionaryKeys() throws {
        // Build a throwaway bundle-like Info.plist on disk so fromBundle(_:)
        // exercises its real Bundle-reading path end to end.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppAboutInfoTests-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let plist: [String: Any] = ["CFBundleShortVersionString": "3.2", "CFBundleVersion": "42"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: directory))

        let info = AppAboutInfo.fromBundle(bundle)

        #expect(info.versionLabel == "Version 3.2 (42)")
    }
}

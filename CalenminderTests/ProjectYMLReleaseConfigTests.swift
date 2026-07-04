import Testing
import Foundation

/// DW-AS.2: static, fast checks that the release-relevant declarations in
/// `project.yml` (the XcodeGen source of truth) are what a clean archive
/// needs - correct marketing/build versions, the app-icon asset wired up,
/// and the 1024x1024 icon file actually present. The archive build itself
/// (zero-warning `xcodebuild archive`) is exercised manually once per this
/// phase and its evidence captured in the phase report, not run here - an
/// archive takes minutes and needs a real toolchain/signing environment,
/// which does not belong in the fast unit suite. This test protects the
/// cheap, deterministic part of DW-AS.2 from silent regression.
struct ProjectYMLReleaseConfigTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CalenminderTests/
            .deletingLastPathComponent() // repo root
    }

    private static func loadProjectYML() throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent("project.yml"), encoding: .utf8)
    }

    @Test("DW-AS.2: project.yml declares CFBundleShortVersionString 1.0 and CFBundleVersion 1")
    func test_DW_AS_2_marketingAndBuildVersionsSet() throws {
        let text = try Self.loadProjectYML()

        let shortVersionOccurrences = text.components(separatedBy: "CFBundleShortVersionString: \"1.0\"").count - 1
        let buildVersionOccurrences = text.components(separatedBy: "CFBundleVersion: \"1\"").count - 1

        #expect(shortVersionOccurrences >= 2, "expected CFBundleShortVersionString \"1.0\" for both the app and widget targets")
        #expect(buildVersionOccurrences >= 2, "expected CFBundleVersion \"1\" for both the app and widget targets")
    }

    @Test("DW-AS.2: project.yml wires the AppIcon asset catalog name to the app target")
    func test_DW_AS_2_appIconAssetNameConfigured() throws {
        let text = try Self.loadProjectYML()

        #expect(text.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"))
    }

    @Test("DW-AS.2: the 1024x1024 app icon asset file exists on disk")
    func test_DW_AS_2_appIconFileExists() throws {
        let iconURL = Self.repoRoot.appendingPathComponent("Calenminder/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

        #expect(FileManager.default.fileExists(atPath: iconURL.path), "missing icon-1024.png")

        let data = try Data(contentsOf: iconURL)
        #expect(data.count > 0)
    }
}

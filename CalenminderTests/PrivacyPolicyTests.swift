import Testing
import Foundation

/// DW-AS.3: `PRIVACY.md` must exist and its central claims must actually be
/// true of the codebase - specifically, that there is no networking layer.
/// Rather than trusting the document's prose, this cross-checks `project.yml`
/// (the XcodeGen source of truth for every target's dependencies) for any
/// networking-flavored SDK dependency; if one is ever added, this test fails
/// until `PRIVACY.md` is revisited.
struct PrivacyPolicyTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CalenminderTests/
            .deletingLastPathComponent() // repo root
    }

    private static func loadFile(_ relativePath: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("DW-AS.3: PRIVACY.md exists and covers the required claims")
    func test_DW_AS_3_privacyPolicyCoversRequiredClaims() throws {
        let text = try Self.loadFile("PRIVACY.md")

        #expect(text.contains("EventKit"), "PRIVACY.md should name EventKit as the calendar/reminders access mechanism")
        #expect(text.localizedCaseInsensitiveContains("on your device") || text.localizedCaseInsensitiveContains("on-device"),
                "PRIVACY.md should state data stays on-device")
        #expect(text.localizedCaseInsensitiveContains("no analytics"), "PRIVACY.md should disclaim analytics")
        #expect(text.localizedCaseInsensitiveContains("badge"), "PRIVACY.md should explain the notification/badge permission's limited purpose")
        #expect(text.contains("github.com/enzonaut/calenminder"), "PRIVACY.md should link back to the public repository")
    }

    @Test("DW-AS.3: PRIVACY.md's 'no network layer' claim holds against project.yml's actual dependencies")
    func test_DW_AS_3_noNetworkingFrameworkLinked() throws {
        let projectYML = try Self.loadFile("project.yml")

        let networkingSDKMarkers = [
            "Network.framework", "CFNetwork.framework", "URLSession", "Alamofire", "CoreTelephony.framework",
        ]
        for marker in networkingSDKMarkers {
            #expect(!projectYML.contains(marker), "project.yml references \(marker); PRIVACY.md's 'no network layer' claim would be false")
        }

        // Only the SDKs this app actually links should be present - all
        // on-device frameworks, none of them networking.
        let expectedSDKs = ["EventKit.framework", "WidgetKit.framework", "UserNotifications.framework", "BackgroundTasks.framework", "AppIntents.framework", "SwiftUI.framework"]
        let sdkLines = projectYML.components(separatedBy: .newlines).filter { $0.contains("sdk:") }
        for line in sdkLines {
            let matchesExpected = expectedSDKs.contains { line.contains($0) }
            #expect(matchesExpected, "project.yml links an SDK not accounted for by PRIVACY.md: \(line.trimmingCharacters(in: .whitespaces))")
        }
    }
}

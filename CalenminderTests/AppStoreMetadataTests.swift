import Testing
import Foundation

/// DW-AS.4: `docs/appstore/metadata.md` must exist, cover every required
/// section, and respect the App Store's hard field limits (subtitle <= 30
/// characters, keywords <= 100 characters and comma-separated with no space
/// after a comma). Reads the committed markdown file directly (same
/// `#filePath`-relative-to-repo-root pattern as `InfoPlistUsageDescriptionTests`)
/// rather than duplicating its content here, so a future edit to the draft
/// is checked against the real limits automatically.
struct AppStoreMetadataTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CalenminderTests/
            .deletingLastPathComponent() // repo root
    }

    private static func loadMetadata() throws -> String {
        let url = repoRoot.appendingPathComponent("docs/appstore/metadata.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Returns the first non-blank, non-comment line under a `## <heading>`
    /// section, i.e. the section's actual value (skipping the field-limit
    /// comment line under Subtitle/Keywords).
    private static func firstValueLine(under heading: String, in text: String) throws -> String {
        let lines = text.components(separatedBy: .newlines)
        guard let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## \(heading)" }) else {
            Issue.record("metadata.md is missing a '## \(heading)' section")
            return ""
        }
        for line in lines[(headingIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("<!--") { continue }
            if trimmed.hasPrefix("##") { break }
            return trimmed
        }
        Issue.record("'## \(heading)' section has no content line")
        return ""
    }

    @Test("DW-AS.4: metadata.md exists and covers every required section")
    func test_DW_AS_4_requiredSectionsPresent() throws {
        let text = try Self.loadMetadata()
        let requiredHeadings = [
            "App Name", "Subtitle", "Description", "Keywords", "Category",
            "Privacy \"Nutrition Label\" Answers", "Age Rating Answers",
            "Support URL", "Privacy Policy URL", "Review Notes for Apple",
        ]
        for heading in requiredHeadings {
            #expect(text.contains("## \(heading)"), "metadata.md is missing '## \(heading)'")
        }
    }

    @Test("DW-AS.4: subtitle is at most 30 characters (App Store hard limit)")
    func test_DW_AS_4_subtitleWithinLimit() throws {
        let subtitle = try Self.firstValueLine(under: "Subtitle", in: Self.loadMetadata())

        #expect(!subtitle.isEmpty)
        #expect(subtitle.count <= 30, "subtitle is \(subtitle.count) characters, over the 30-character limit: \"\(subtitle)\"")
    }

    @Test("DW-AS.4: keywords are at most 100 characters, comma-separated with no space after a comma")
    func test_DW_AS_4_keywordsWithinLimitAndFormat() throws {
        let keywords = try Self.firstValueLine(under: "Keywords", in: Self.loadMetadata())

        #expect(!keywords.isEmpty)
        #expect(keywords.count <= 100, "keywords are \(keywords.count) characters, over the 100-character limit: \"\(keywords)\"")
        #expect(!keywords.contains(", "), "keywords must not contain a space after a comma: \"\(keywords)\"")
    }

    @Test("DW-AS.4: category is a single recognizable App Store category")
    func test_DW_AS_4_categoryPresent() throws {
        let category = try Self.firstValueLine(under: "Category", in: Self.loadMetadata())

        #expect(category == "Productivity")
    }
}

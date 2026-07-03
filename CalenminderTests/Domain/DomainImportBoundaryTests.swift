import Testing
import Foundation

/// DW-2.1: the Domain layer must import none of EventKit/UIKit/networking (or
/// other UI/extension frameworks). Because those are system frameworks
/// importable from any target, this cannot be enforced by target isolation - it
/// is enforced by scanning the Domain sources. The scan locates the Domain
/// directory from this test's own compile-time `#filePath` (tests run on the
/// same host, so the source tree is reachable) and fails loudly if the
/// directory or any Swift files are missing, so a broken path can never pass.
struct DomainImportBoundaryTests {
    static let forbiddenModules = [
        "EventKit", "UIKit", "AppKit", "WidgetKit", "SwiftUI", "AppIntents", "Network",
    ]

    @Test("DW-2.1: Domain sources import no forbidden (EventKit/UIKit/networking) modules")
    func test_DW_2_1_domainSourcesHaveNoForbiddenImports() throws {
        let dir = Self.domainDirectory()

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory)
        #expect(exists, "Domain directory not found at \(dir.path)")
        #expect(isDirectory.boolValue, "Domain path is not a directory: \(dir.path)")

        let swiftFiles = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        // Sanity: if we scanned nothing, the path logic is wrong - fail, don't pass.
        #expect(!swiftFiles.isEmpty, "No Swift files scanned in \(dir.path)")

        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard Self.isImportLine(line) else { continue }
                for module in Self.forbiddenModules {
                    #expect(
                        !Self.importsModule(line, module),
                        "\(file.lastPathComponent) imports forbidden module \(module): \(line)"
                    )
                }
            }
        }
    }

    @Test("Import scanner detects a forbidden import in representative lines")
    func scannerDetectsForbiddenImports() {
        // Guards the DW-2.1 test against silently never matching.
        #expect(Self.isImportLine("import EventKit"))
        #expect(Self.importsModule("import EventKit", "EventKit"))
        #expect(Self.importsModule("@testable import UIKit", "UIKit"))
        #expect(Self.importsModule("@_exported import EventKit.EKEvent", "EventKit"))
        #expect(!Self.importsModule("import Foundation", "EventKit"))
        #expect(!Self.isImportLine("// this comment mentions import EventKit"))
        #expect(!Self.isImportLine("let importer = 3"))
    }

    // MARK: - Helpers

    static func domainDirectory(file: String = #filePath) -> URL {
        // file = <repo>/CalenminderTests/Domain/DomainImportBoundaryTests.swift
        URL(fileURLWithPath: file)
            .deletingLastPathComponent()   // .../CalenminderTests/Domain
            .deletingLastPathComponent()   // .../CalenminderTests
            .deletingLastPathComponent()   // .../<repo>
            .appendingPathComponent("CalenminderKit/Domain", isDirectory: true)
    }

    /// A real import declaration (possibly attributed, e.g. `@testable import`),
    /// not a comment or an identifier that merely contains "import".
    static func isImportLine(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { return false }
        if trimmed.hasPrefix("import ") { return true }
        return trimmed.hasPrefix("@") && trimmed.contains(" import ")
    }

    static func importsModule(_ line: String, _ module: String) -> Bool {
        guard let range = line.range(of: "import ") else { return false }
        let after = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let firstToken = after
            .split(whereSeparator: { $0 == " " || $0 == "." || $0 == "\t" })
            .first
            .map(String.init) ?? ""
        return firstToken == module
    }
}

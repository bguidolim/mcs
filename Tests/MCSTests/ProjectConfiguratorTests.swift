import Foundation
import Testing

@testable import mcs

@Suite("ProjectConfigurator — writeClaudeLocal")
struct WriteClaudeLocalTests {
    private let output = CLIOutput(colorsEnabled: false)

    private func makeTmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-projconf-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeConfigurator() -> ProjectConfigurator {
        let env = Environment()
        return ProjectConfigurator(
            environment: env,
            output: output,
            shell: ShellRunner(environment: env)
        )
    }

    private func coreContribution(_ content: String = "Core rules") -> TemplateContribution {
        TemplateContribution(
            sectionIdentifier: "core",
            templateContent: content,
            placeholders: []
        )
    }

    private func iosContribution(_ content: String = "iOS rules for __PROJECT__") -> TemplateContribution {
        TemplateContribution(
            sectionIdentifier: "ios",
            templateContent: content,
            placeholders: ["__PROJECT__"]
        )
    }

    // MARK: - Fresh file (no existing CLAUDE.local.md)

    @Test("Creates CLAUDE.local.md with section markers from scratch")
    func freshFileCreation() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configurator = makeConfigurator()
        try configurator.writeClaudeLocal(
            at: tmpDir,
            contributions: [coreContribution()],
            values: [:]
        )

        let path = tmpDir.appendingPathComponent("CLAUDE.local.md")
        let content = try String(contentsOf: path, encoding: .utf8)

        let sections = TemplateComposer.parseSections(from: content)
        #expect(sections.count == 1)
        #expect(sections[0].identifier == "core")
        #expect(sections[0].content == "Core rules")
    }

    // MARK: - v1 migration (file exists, no markers)

    @Test("v1 file without markers is replaced with v2 composed output")
    func v1MigrationReplacesWithMarkers() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Write a v1 file (no section markers)
        let claudeLocal = tmpDir.appendingPathComponent("CLAUDE.local.md")
        try "Old v1 content without any markers".write(
            to: claudeLocal, atomically: true, encoding: .utf8
        )

        let configurator = makeConfigurator()
        try configurator.writeClaudeLocal(
            at: tmpDir,
            contributions: [coreContribution("New core")],
            values: [:]
        )

        let content = try String(contentsOf: claudeLocal, encoding: .utf8)

        // Should have proper v2 markers
        let sections = TemplateComposer.parseSections(from: content)
        #expect(sections.count == 1)
        #expect(sections[0].identifier == "core")
        #expect(sections[0].content == "New core")

        // Old v1 content should not be present
        #expect(!content.contains("Old v1 content"))
    }

    @Test("v1 migration creates backup of original file")
    func v1MigrationCreatesBackup() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let claudeLocal = tmpDir.appendingPathComponent("CLAUDE.local.md")
        try "Old v1 content".write(to: claudeLocal, atomically: true, encoding: .utf8)

        let configurator = makeConfigurator()
        try configurator.writeClaudeLocal(
            at: tmpDir,
            contributions: [coreContribution()],
            values: [:]
        )

        // Check a backup was created
        let files = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        let backups = files.filter { $0.contains("CLAUDE.local.md.backup") }
        #expect(!backups.isEmpty)
    }

    // MARK: - v2 update (file exists with markers)

    @Test("v2 file with markers is updated in place")
    func v2UpdatePreservesStructure() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Write a v2 file
        let claudeLocal = tmpDir.appendingPathComponent("CLAUDE.local.md")
        let v2Content = TemplateComposer.compose(coreContent: "Old core")
        try v2Content.write(to: claudeLocal, atomically: true, encoding: .utf8)

        let configurator = makeConfigurator()
        try configurator.writeClaudeLocal(
            at: tmpDir,
            contributions: [coreContribution("Updated core")],
            values: [:]
        )

        let content = try String(contentsOf: claudeLocal, encoding: .utf8)
        let sections = TemplateComposer.parseSections(from: content)
        #expect(sections.count == 1)
        #expect(sections[0].content == "Updated core")
        #expect(!content.contains("Old core"))
    }

    @Test("v2 update preserves user content outside markers")
    func v2UpdatePreservesUserContent() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let claudeLocal = tmpDir.appendingPathComponent("CLAUDE.local.md")
        let v2Content = TemplateComposer.compose(coreContent: "Core")
            + "\n\nMy custom notes\n"
        try v2Content.write(to: claudeLocal, atomically: true, encoding: .utf8)

        let configurator = makeConfigurator()
        try configurator.writeClaudeLocal(
            at: tmpDir,
            contributions: [coreContribution("New core")],
            values: [:]
        )

        let content = try String(contentsOf: claudeLocal, encoding: .utf8)
        #expect(content.contains("New core"))
        #expect(content.contains("My custom notes"))
    }

    // MARK: - Template substitution

    // MARK: - Section removal on unconfigure

    @Test("Unconfiguring a pack removes its template section from CLAUDE.local.md")
    func unconfigureRemovesTemplateSection() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Set up a CLAUDE.local.md with core + ios sections
        let claudeLocal = tmpDir.appendingPathComponent("CLAUDE.local.md")
        let composed = TemplateComposer.compose(
            coreContent: "Core rules",
            packContributions: [iosContribution("iOS rules")],
            values: [:]
        )
        try composed.write(to: claudeLocal, atomically: true, encoding: .utf8)

        // Verify both sections exist
        let before = try String(contentsOf: claudeLocal, encoding: .utf8)
        let sectionsBefore = TemplateComposer.parseSections(from: before)
        #expect(sectionsBefore.count == 2)

        // Simulate unconfigure by removing the ios section (same logic as unconfigurePack)
        let artifacts = PackArtifactRecord(templateSections: ["ios"])
        var updated = before
        for sectionID in artifacts.templateSections {
            updated = TemplateComposer.removeSection(in: updated, sectionIdentifier: sectionID)
        }
        try updated.write(to: claudeLocal, atomically: true, encoding: .utf8)

        // Verify only core remains
        let after = try String(contentsOf: claudeLocal, encoding: .utf8)
        let sectionsAfter = TemplateComposer.parseSections(from: after)
        #expect(sectionsAfter.count == 1)
        #expect(sectionsAfter[0].identifier == "core")
        #expect(!after.contains("mcs:begin ios"))
        #expect(!after.contains("mcs:end ios"))
    }

    // MARK: - Template substitution

    @Test("Pack template values are substituted during compose")
    func packValuesSubstituted() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configurator = makeConfigurator()
        try configurator.writeClaudeLocal(
            at: tmpDir,
            contributions: [coreContribution(), iosContribution()],
            values: ["REPO_NAME": "my-repo", "PROJECT": "MyApp.xcodeproj"]
        )

        let claudeLocal = tmpDir.appendingPathComponent("CLAUDE.local.md")
        let content = try String(contentsOf: claudeLocal, encoding: .utf8)

        #expect(content.contains("MyApp.xcodeproj"))
        #expect(!content.contains("__PROJECT__"))
    }
}

import Foundation
@testable import mcs
import Testing

// MARK: - Cooldown Tests

struct UpdateCheckerCooldownTests {
    private func makeTmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-updatechecker-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeChecker(home: URL) -> UpdateChecker {
        let env = Environment(home: home)
        let shell = ShellRunner(environment: env)
        return UpdateChecker(environment: env, shell: shell)
    }

    @Test("shouldCheck returns true when file does not exist")
    func shouldCheckWhenFileMissing() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let checker = makeChecker(home: tmpDir)
        #expect(checker.shouldCheck())
    }

    @Test("shouldCheck returns true when timestamp is expired")
    func shouldCheckWhenExpired() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = Environment(home: tmpDir)
        let mcsDir = tmpDir.appendingPathComponent(".mcs")
        try FileManager.default.createDirectory(at: mcsDir, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        let oldDate = Date().addingTimeInterval(-700_000) // ~8 days ago
        let timestamp = formatter.string(from: oldDate)
        try timestamp.write(to: env.lastUpdateCheckFile, atomically: true, encoding: .utf8)

        let checker = makeChecker(home: tmpDir)
        #expect(checker.shouldCheck())
    }

    @Test("shouldCheck returns false when timestamp is fresh")
    func shouldCheckWhenFresh() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = Environment(home: tmpDir)
        let mcsDir = tmpDir.appendingPathComponent(".mcs")
        try FileManager.default.createDirectory(at: mcsDir, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        let recentDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let timestamp = formatter.string(from: recentDate)
        try timestamp.write(to: env.lastUpdateCheckFile, atomically: true, encoding: .utf8)

        let checker = makeChecker(home: tmpDir)
        #expect(!checker.shouldCheck())
    }

    @Test("shouldCheck returns true when file content is corrupt")
    func shouldCheckWhenCorrupt() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = Environment(home: tmpDir)
        let mcsDir = tmpDir.appendingPathComponent(".mcs")
        try FileManager.default.createDirectory(at: mcsDir, withIntermediateDirectories: true)

        try "not-a-date".write(to: env.lastUpdateCheckFile, atomically: true, encoding: .utf8)

        let checker = makeChecker(home: tmpDir)
        #expect(checker.shouldCheck())
    }

    @Test("recordCheckTimestamp writes a parseable ISO8601 timestamp")
    func recordTimestamp() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let checker = makeChecker(home: tmpDir)
        checker.recordCheckTimestamp()

        let env = Environment(home: tmpDir)
        let content = try String(contentsOf: env.lastUpdateCheckFile, encoding: .utf8)
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: content.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(date != nil)
    }
}

// MARK: - Parsing Tests

struct UpdateCheckerParsingTests {
    @Test("parseRemoteSHA extracts SHA from valid ls-remote output")
    func parseValidSHA() {
        let output = "abc123def456789\tHEAD\n"
        let sha = UpdateChecker.parseRemoteSHA(from: output)
        #expect(sha == "abc123def456789")
    }

    @Test("parseRemoteSHA returns nil for empty output")
    func parseEmptyOutput() {
        #expect(UpdateChecker.parseRemoteSHA(from: "") == nil)
        #expect(UpdateChecker.parseRemoteSHA(from: "   ") == nil)
    }

    @Test("parseRemoteSHA handles multi-line output (takes first line)")
    func parseMultiLine() {
        let output = """
        abc123\trefs/heads/main
        def456\trefs/heads/develop
        """
        let sha = UpdateChecker.parseRemoteSHA(from: output)
        #expect(sha == "abc123")
    }

    @Test("parseLatestTag finds the highest CalVer tag")
    func parseLatestTagMultiple() {
        let output = """
        aaa\trefs/tags/2026.1.1
        bbb\trefs/tags/2026.3.22
        ccc\trefs/tags/2026.2.15
        ddd\trefs/tags/2025.12.1
        """
        let latest = UpdateChecker.parseLatestTag(from: output)
        #expect(latest == "2026.3.22")
    }

    @Test("parseLatestTag returns nil for empty output")
    func parseLatestTagEmpty() {
        #expect(UpdateChecker.parseLatestTag(from: "") == nil)
    }

    @Test("parseLatestTag skips non-CalVer tags")
    func parseLatestTagSkipsNonCalVer() {
        let output = """
        aaa\trefs/tags/v1.0
        bbb\trefs/tags/2026.3.22
        ccc\trefs/tags/beta
        """
        let latest = UpdateChecker.parseLatestTag(from: output)
        #expect(latest == "2026.3.22")
    }

    @Test("parseLatestTag returns nil when no CalVer tags exist")
    func parseLatestTagNoCalVer() {
        let output = """
        aaa\trefs/tags/v1.0
        bbb\trefs/tags/release-candidate
        """
        #expect(UpdateChecker.parseLatestTag(from: output) == nil)
    }
}

// MARK: - Version Comparison Tests

struct UpdateCheckerVersionTests {
    @Test("isNewer detects newer version")
    func newerVersion() {
        #expect(UpdateChecker.isNewer(candidate: "2026.4.1", than: "2026.3.22"))
        #expect(UpdateChecker.isNewer(candidate: "2027.1.1", than: "2026.12.31"))
        #expect(UpdateChecker.isNewer(candidate: "2026.3.23", than: "2026.3.22"))
    }

    @Test("isNewer returns false for same version")
    func sameVersion() {
        #expect(!UpdateChecker.isNewer(candidate: "2026.3.22", than: "2026.3.22"))
    }

    @Test("isNewer returns false for older version")
    func olderVersion() {
        #expect(!UpdateChecker.isNewer(candidate: "2026.3.21", than: "2026.3.22"))
        #expect(!UpdateChecker.isNewer(candidate: "2025.12.31", than: "2026.1.1"))
    }

    @Test("isNewer returns false for unparseable versions")
    func unparseable() {
        #expect(!UpdateChecker.isNewer(candidate: "invalid", than: "2026.3.22"))
        #expect(!UpdateChecker.isNewer(candidate: "2026.3.22", than: "invalid"))
    }
}

// MARK: - CheckResult Tests

struct UpdateCheckerResultTests {
    @Test("isEmpty returns true when no updates")
    func emptyResult() {
        let result = UpdateChecker.CheckResult(packUpdates: [], cliUpdate: nil)
        #expect(result.isEmpty)
    }

    @Test("isEmpty returns false with pack updates")
    func nonEmptyPackResult() {
        let result = UpdateChecker.CheckResult(
            packUpdates: [UpdateChecker.PackUpdate(
                identifier: "test", displayName: "Test", localSHA: "aaa", remoteSHA: "bbb"
            )],
            cliUpdate: nil
        )
        #expect(!result.isEmpty)
    }

    @Test("isEmpty returns false with CLI update")
    func nonEmptyCLIResult() {
        let result = UpdateChecker.CheckResult(
            packUpdates: [],
            cliUpdate: UpdateChecker.CLIUpdate(currentVersion: "1.0.0", latestVersion: "2.0.0")
        )
        #expect(!result.isEmpty)
    }
}

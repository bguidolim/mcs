import Foundation
@testable import mcs
import Testing

// MARK: - Cache Tests

struct UpdateCheckerCacheTests {
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

    private func writeCacheFile(at env: Environment, timestamp: Date, result: UpdateChecker.CheckResult) throws {
        let cached = UpdateChecker.CachedResult(
            timestamp: ISO8601DateFormatter().string(from: timestamp),
            result: result
        )
        let dir = env.updateCheckCacheFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(cached)
        try data.write(to: env.updateCheckCacheFile, options: .atomic)
    }

    private var emptyResult: UpdateChecker.CheckResult {
        UpdateChecker.CheckResult(packUpdates: [], cliUpdate: nil)
    }

    @Test("loadCache returns nil when file does not exist")
    func cacheNilWhenMissing() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let checker = makeChecker(home: tmpDir)
        #expect(checker.loadCache() == nil)
    }

    @Test("loadCache returns cached result when file is valid")
    func cacheLoadsValidFile() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = Environment(home: tmpDir)
        try writeCacheFile(at: env, timestamp: Date().addingTimeInterval(-3600), result: emptyResult)

        let checker = makeChecker(home: tmpDir)
        let cached = checker.loadCache()
        #expect(cached != nil)
        #expect(cached?.result.isEmpty == true)
    }

    @Test("loadCache returns nil when file content is corrupt")
    func cacheNilWhenCorrupt() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = Environment(home: tmpDir)
        let mcsDir = tmpDir.appendingPathComponent(".mcs")
        try FileManager.default.createDirectory(at: mcsDir, withIntermediateDirectories: true)
        try "not-json".write(to: env.updateCheckCacheFile, atomically: true, encoding: .utf8)

        let checker = makeChecker(home: tmpDir)
        #expect(checker.loadCache() == nil)
    }

    @Test("saveCache writes a decodable cache file")
    func saveCacheRoundtrip() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let checker = makeChecker(home: tmpDir)
        let result = UpdateChecker.CheckResult(
            packUpdates: [UpdateChecker.PackUpdate(
                identifier: "test", displayName: "Test", localSHA: "aaa", remoteSHA: "bbb"
            )],
            cliUpdate: nil
        )
        checker.saveCache(result)

        let cached = checker.loadCache()
        #expect(cached != nil)
        #expect(cached?.result.packUpdates.count == 1)
        #expect(cached?.result.packUpdates.first?.identifier == "test")
    }

    @Test("loadCache returns nil when CLI version changed")
    func cacheInvalidatedOnCLIUpgrade() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = Environment(home: tmpDir)
        let staleResult = UpdateChecker.CheckResult(
            packUpdates: [],
            cliUpdate: UpdateChecker.CLIUpdate(currentVersion: "1999.1.1", latestVersion: "2000.1.1")
        )
        try writeCacheFile(at: env, timestamp: Date(), result: staleResult)

        let checker = makeChecker(home: tmpDir)
        #expect(checker.loadCache() == nil)
    }

    @Test("invalidateCache deletes the cache file")
    func invalidateCache() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let checker = makeChecker(home: tmpDir)
        checker.saveCache(emptyResult)

        let env = Environment(home: tmpDir)
        #expect(FileManager.default.fileExists(atPath: env.updateCheckCacheFile.path))

        UpdateChecker.invalidateCache(environment: env)
        #expect(!FileManager.default.fileExists(atPath: env.updateCheckCacheFile.path))
    }
}

// MARK: - performCheck Tests

struct UpdateCheckerPerformCheckTests {
    private func makeTmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-performcheck-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeChecker(home: URL) -> UpdateChecker {
        let env = Environment(home: home)
        let shell = ShellRunner(environment: env)
        return UpdateChecker(environment: env, shell: shell)
    }

    private func writeFreshCache(at env: Environment, result: UpdateChecker.CheckResult) throws {
        let cached = UpdateChecker.CachedResult(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            result: result
        )
        let dir = env.updateCheckCacheFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(cached)
        try data.write(to: env.updateCheckCacheFile, options: .atomic)
    }

    @Test("Returns cached result when cache is fresh")
    func cachedResultReturnedByDefault() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = Environment(home: tmpDir)
        let cachedResult = UpdateChecker.CheckResult(
            packUpdates: [UpdateChecker.PackUpdate(
                identifier: "cached-pack", displayName: "Cached", localSHA: "aaa", remoteSHA: "bbb"
            )],
            cliUpdate: nil
        )
        try writeFreshCache(at: env, result: cachedResult)

        let checker = makeChecker(home: tmpDir)
        let result = checker.performCheck(entries: [], checkPacks: true, checkCLI: false)

        // Should return cached result, not do network calls (entries is empty so network would return nothing)
        #expect(result.packUpdates.count == 1)
        #expect(result.packUpdates.first?.identifier == "cached-pack")
    }

    @Test("forceRefresh bypasses cache and does fresh check")
    func forceRefreshBypassesCache() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = Environment(home: tmpDir)
        let cachedResult = UpdateChecker.CheckResult(
            packUpdates: [UpdateChecker.PackUpdate(
                identifier: "stale", displayName: "Stale", localSHA: "aaa", remoteSHA: "bbb"
            )],
            cliUpdate: nil
        )
        try writeFreshCache(at: env, result: cachedResult)

        let checker = makeChecker(home: tmpDir)
        let result = checker.performCheck(entries: [], forceRefresh: true, checkPacks: true, checkCLI: false)

        // Should NOT return cached "stale" pack — should do fresh check with empty entries
        #expect(result.packUpdates.isEmpty)
    }

    @Test("Stale cache triggers fresh check")
    func staleCacheTriggersFreshCheck() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = Environment(home: tmpDir)
        let staleResult = UpdateChecker.CheckResult(
            packUpdates: [UpdateChecker.PackUpdate(
                identifier: "old-pack", displayName: "Old", localSHA: "aaa", remoteSHA: "bbb"
            )],
            cliUpdate: nil
        )
        // Write cache with timestamp older than 24 hours
        let staleTimestamp = Date().addingTimeInterval(-90000)
        let cached = UpdateChecker.CachedResult(
            timestamp: ISO8601DateFormatter().string(from: staleTimestamp),
            result: staleResult
        )
        let dir = env.updateCheckCacheFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(cached)
        try data.write(to: env.updateCheckCacheFile, options: .atomic)

        let checker = makeChecker(home: tmpDir)
        let result = checker.performCheck(entries: [], checkPacks: true, checkCLI: false)

        // Cache is stale (>24h), so should do fresh check with empty entries → empty result
        #expect(result.packUpdates.isEmpty)
    }

    @Test("performCheck saves cache after network check")
    func savesCache() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = Environment(home: tmpDir)
        #expect(!FileManager.default.fileExists(atPath: env.updateCheckCacheFile.path))

        let checker = makeChecker(home: tmpDir)
        _ = checker.performCheck(entries: [], checkPacks: true, checkCLI: false)

        #expect(FileManager.default.fileExists(atPath: env.updateCheckCacheFile.path))
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
        #expect(VersionCompare.isNewer(candidate: "2026.4.1", than: "2026.3.22"))
        #expect(VersionCompare.isNewer(candidate: "2027.1.1", than: "2026.12.31"))
        #expect(VersionCompare.isNewer(candidate: "2026.3.23", than: "2026.3.22"))
    }

    @Test("isNewer returns false for same version")
    func sameVersion() {
        #expect(!VersionCompare.isNewer(candidate: "2026.3.22", than: "2026.3.22"))
    }

    @Test("isNewer returns false for older version")
    func olderVersion() {
        #expect(!VersionCompare.isNewer(candidate: "2026.3.21", than: "2026.3.22"))
        #expect(!VersionCompare.isNewer(candidate: "2025.12.31", than: "2026.1.1"))
    }

    @Test("isNewer returns false for unparseable versions")
    func unparseable() {
        #expect(!VersionCompare.isNewer(candidate: "invalid", than: "2026.3.22"))
        #expect(!VersionCompare.isNewer(candidate: "2026.3.22", than: "invalid"))
    }
}

// MARK: - Hook Management Tests

struct UpdateCheckerHookTests {
    private func makeTmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-hook-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("addHook creates SessionStart entry with correct command and metadata")
    func addHookCreatesEntry() {
        var settings = Settings()
        let added = UpdateChecker.addHook(to: &settings)
        #expect(added)

        let groups = settings.hooks?[Constants.HookEvent.sessionStart.rawValue] ?? []
        #expect(groups.count == 1)
        let entry = groups.first?.hooks?.first
        #expect(entry?.command == "mcs check-updates --hook")
        #expect(entry?.timeout == 30)
        #expect(entry?.statusMessage == "Checking for updates...")
        #expect(entry?.type == "command")
    }

    @Test("addHook is idempotent")
    func addHookIdempotent() {
        var settings = Settings()
        UpdateChecker.addHook(to: &settings)
        let secondAdd = UpdateChecker.addHook(to: &settings)
        #expect(!secondAdd) // no-op, already present
        #expect(settings.hooks?[Constants.HookEvent.sessionStart.rawValue]?.count == 1)
    }

    @Test("removeHook removes the update check entry")
    func removeHookRemovesEntry() {
        var settings = Settings()
        UpdateChecker.addHook(to: &settings)
        let removed = UpdateChecker.removeHook(from: &settings)
        #expect(removed)
        #expect(settings.hooks == nil)
    }

    @Test("removeHook preserves other SessionStart hooks")
    func removeHookPreservesOthers() {
        var settings = Settings()
        settings.addHookEntry(event: "SessionStart", command: "bash .claude/hooks/startup.sh")
        UpdateChecker.addHook(to: &settings)

        UpdateChecker.removeHook(from: &settings)
        let groups = settings.hooks?["SessionStart"] ?? []
        #expect(groups.count == 1)
        #expect(groups.first?.hooks?.first?.command == "bash .claude/hooks/startup.sh")
    }

    @Test("addHook + removeHook round-trip leaves settings clean")
    func hookRoundTrip() {
        var settings = Settings()
        UpdateChecker.addHook(to: &settings)
        UpdateChecker.removeHook(from: &settings)
        #expect(settings.hooks == nil)
    }

    @Test("syncHook adds hook when config enabled")
    func syncHookAdds() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = Environment(home: tmpDir)
        // Create empty settings.json
        let claudeDir = tmpDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try "{}".write(to: env.claudeSettings, atomically: true, encoding: .utf8)

        var config = MCSConfig()
        config.updateCheckPacks = true
        let output = CLIOutput()

        UpdateChecker.syncHook(config: config, env: env, output: output)

        let settings = try Settings.load(from: env.claudeSettings)
        let groups = settings.hooks?[Constants.HookEvent.sessionStart.rawValue] ?? []
        #expect(groups.count == 1)
        #expect(groups.first?.hooks?.first?.command == UpdateChecker.hookCommand)
    }

    @Test("syncHook removes hook when config disabled")
    func syncHookRemoves() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let env = Environment(home: tmpDir)
        let claudeDir = tmpDir.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        // Pre-populate with the hook
        var initial = Settings()
        UpdateChecker.addHook(to: &initial)
        try initial.save(to: env.claudeSettings)

        var config = MCSConfig()
        config.updateCheckPacks = false
        config.updateCheckCLI = false
        let output = CLIOutput()

        UpdateChecker.syncHook(config: config, env: env, output: output)

        let settings = try Settings.load(from: env.claudeSettings)
        #expect(settings.hooks == nil)
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

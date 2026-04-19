import Foundation
@testable import mcs
import Testing

struct EnvironmentTests {
    /// Create a unique temp directory simulating a home directory.
    private func makeTmpHome() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-env-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Path construction

    @Test("Environment paths are relative to home directory")
    func pathsRelativeToHome() throws {
        let home = try makeTmpHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let env = Environment(home: home)

        #expect(env.claudeDirectory.path == home.appendingPathComponent(".claude").path)
        #expect(env.claudeJSON.path == home.appendingPathComponent(".claude.json").path)
        #expect(env.claudeSettings.path ==
            home.appendingPathComponent(".claude/settings.json").path)
    }

    // MARK: - isInsideClaudeHome

    @Test("isInsideClaudeHome: true for claudeDirectory itself when .claude.json exists")
    func isInsideClaudeHomeExactMatch() throws {
        let home = try makeClaudeHome(withJSON: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        #expect(env.isInsideClaudeHome(env.claudeDirectory))
    }

    @Test("isInsideClaudeHome: true for nested paths inside claudeDirectory")
    func isInsideClaudeHomeNested() throws {
        let home = try makeClaudeHome(withJSON: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        let nested = env.claudeDirectory.appendingPathComponent("skills/foo")
        #expect(env.isInsideClaudeHome(nested))
    }

    @Test("isInsideClaudeHome: false when .claude.json is missing (fresh install edge case)")
    func isInsideClaudeHomeMissingSibling() throws {
        let home = try makeClaudeHome(withJSON: false)
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        #expect(!env.isInsideClaudeHome(env.claudeDirectory))
    }

    @Test("isInsideClaudeHome: false for unrelated paths")
    func isInsideClaudeHomeUnrelatedPath() throws {
        let home = try makeClaudeHome(withJSON: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        #expect(!env.isInsideClaudeHome(home.appendingPathComponent("project")))
        #expect(!env.isInsideClaudeHome(URL(fileURLWithPath: "/tmp")))
    }

    @Test("isInsideClaudeHome: false for sibling dir that merely shares a name prefix")
    func isInsideClaudeHomePrefixCollision() throws {
        let home = try makeClaudeHome(withJSON: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        // `/~/.claudex` must not be considered inside `/~/.claude`
        let spoof = home.appendingPathComponent(".claudex")
        #expect(!env.isInsideClaudeHome(spoof))
    }

    @Test("isInsideClaudeHome: true for $HOME itself when layout matches")
    func isInsideClaudeHomeExactHome() throws {
        let home = try makeClaudeHome(withJSON: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        #expect(env.isInsideClaudeHome(env.homeDirectory))
    }

    @Test("isInsideClaudeHome: false for $HOME/subdir (legitimate project locations)")
    func isInsideClaudeHomeSiblingSubdir() throws {
        let home = try makeClaudeHome(withJSON: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        let subdir = home.appendingPathComponent("Documents")
        #expect(!env.isInsideClaudeHome(subdir))
    }

    @Test("isInsideClaudeHome: false for $HOME match when .claude.json missing")
    func isInsideClaudeHomeExactHomeWithoutSibling() throws {
        let home = try makeClaudeHome(withJSON: false)
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        #expect(!env.isInsideClaudeHome(env.homeDirectory))
    }
}

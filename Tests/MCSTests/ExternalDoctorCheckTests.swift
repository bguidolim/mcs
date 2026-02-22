import Foundation
import Testing

@testable import mcs

@Suite("ExternalDoctorCheck")
struct ExternalDoctorCheckTests {
    /// Create a unique temp directory for each test.
    private func makeTmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-extdoc-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeScriptRunner() -> ScriptRunner {
        let env = Environment()
        let shell = ShellRunner(environment: env)
        let output = CLIOutput(colorsEnabled: false)
        return ScriptRunner(shell: shell, output: output)
    }

    // MARK: - ExternalCommandExistsCheck

    @Test("Command exists check passes for known command")
    func commandExistsKnown() {
        let check = ExternalCommandExistsCheck(
            name: "ls",
            section: "Dependencies",
            command: "/bin/ls",
            args: [],
            fixCommand: nil
        )
        let result = check.check()
        if case .pass = result {
            // expected
        } else {
            Issue.record("Expected .pass, got \(result)")
        }
    }

    @Test("Command exists check fails for unknown command")
    func commandExistsUnknown() {
        let check = ExternalCommandExistsCheck(
            name: "nonexistent-tool",
            section: "Dependencies",
            command: "nonexistent-tool-xyz-12345",
            args: [],
            fixCommand: nil
        )
        let result = check.check()
        if case .fail = result {
            // expected
        } else {
            Issue.record("Expected .fail, got \(result)")
        }
    }

    @Test("Command exists fix returns notFixable when no fix command")
    func commandExistsNoFix() {
        let check = ExternalCommandExistsCheck(
            name: "test",
            section: "Dependencies",
            command: "nonexistent",
            args: [],
            fixCommand: nil
        )
        let result = check.fix()
        if case .notFixable = result {
            // expected
        } else {
            Issue.record("Expected .notFixable, got \(result)")
        }
    }

    // MARK: - ExternalFileExistsCheck

    @Test("File exists check passes for existing file")
    func fileExistsPass() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appendingPathComponent("test.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)

        let check = ExternalFileExistsCheck(
            name: "test file",
            section: "Files",
            path: file.path,
            scope: .global,
            projectRoot: nil
        )
        let result = check.check()
        if case .pass = result {
            // expected
        } else {
            Issue.record("Expected .pass, got \(result)")
        }
    }

    @Test("File exists check fails for missing file")
    func fileExistsFail() {
        let check = ExternalFileExistsCheck(
            name: "missing file",
            section: "Files",
            path: "/tmp/nonexistent-\(UUID().uuidString).txt",
            scope: .global,
            projectRoot: nil
        )
        let result = check.check()
        if case .fail = result {
            // expected
        } else {
            Issue.record("Expected .fail, got \(result)")
        }
    }

    @Test("File exists check skips for project scope without project root")
    func fileExistsSkipNoProject() {
        let check = ExternalFileExistsCheck(
            name: "project file",
            section: "Files",
            path: "some-file.txt",
            scope: .project,
            projectRoot: nil
        )
        let result = check.check()
        if case .skip = result {
            // expected
        } else {
            Issue.record("Expected .skip, got \(result)")
        }
    }

    @Test("File exists check resolves project-scoped path")
    func fileExistsProjectScope() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appendingPathComponent("config.yml")
        try "key: value".write(to: file, atomically: true, encoding: .utf8)

        let check = ExternalFileExistsCheck(
            name: "config",
            section: "Files",
            path: "config.yml",
            scope: .project,
            projectRoot: tmpDir
        )
        let result = check.check()
        if case .pass = result {
            // expected
        } else {
            Issue.record("Expected .pass, got \(result)")
        }
    }

    // MARK: - ExternalDirectoryExistsCheck

    @Test("Directory exists check passes for existing directory")
    func directoryExistsPass() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let check = ExternalDirectoryExistsCheck(
            name: "tmp dir",
            section: "Files",
            path: tmpDir.path,
            scope: .global,
            projectRoot: nil
        )
        let result = check.check()
        if case .pass = result {
            // expected
        } else {
            Issue.record("Expected .pass, got \(result)")
        }
    }

    @Test("Directory exists check fails for missing directory")
    func directoryExistsFail() {
        let check = ExternalDirectoryExistsCheck(
            name: "missing dir",
            section: "Files",
            path: "/tmp/nonexistent-dir-\(UUID().uuidString)",
            scope: .global,
            projectRoot: nil
        )
        let result = check.check()
        if case .fail = result {
            // expected
        } else {
            Issue.record("Expected .fail, got \(result)")
        }
    }

    // MARK: - ExternalFileContainsCheck

    @Test("File contains check passes when pattern is present")
    func fileContainsPass() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appendingPathComponent("config.txt")
        try "enable_feature=true\nmode=production".write(to: file, atomically: true, encoding: .utf8)

        let check = ExternalFileContainsCheck(
            name: "feature flag",
            section: "Configuration",
            path: file.path,
            pattern: "enable_feature=true",
            scope: .global,
            projectRoot: nil
        )
        let result = check.check()
        if case .pass = result {
            // expected
        } else {
            Issue.record("Expected .pass, got \(result)")
        }
    }

    @Test("File contains check fails when pattern is absent")
    func fileContainsFail() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appendingPathComponent("config.txt")
        try "enable_feature=false".write(to: file, atomically: true, encoding: .utf8)

        let check = ExternalFileContainsCheck(
            name: "feature flag",
            section: "Configuration",
            path: file.path,
            pattern: "enable_feature=true",
            scope: .global,
            projectRoot: nil
        )
        let result = check.check()
        if case .fail = result {
            // expected
        } else {
            Issue.record("Expected .fail, got \(result)")
        }
    }

    // MARK: - ExternalFileNotContainsCheck

    @Test("File not contains check passes when pattern is absent")
    func fileNotContainsPass() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appendingPathComponent("clean.txt")
        try "safe content here".write(to: file, atomically: true, encoding: .utf8)

        let check = ExternalFileNotContainsCheck(
            name: "no secrets",
            section: "Security",
            path: file.path,
            pattern: "SECRET_KEY=",
            scope: .global,
            projectRoot: nil
        )
        let result = check.check()
        if case .pass = result {
            // expected
        } else {
            Issue.record("Expected .pass, got \(result)")
        }
    }

    @Test("File not contains check fails when pattern is present")
    func fileNotContainsFail() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let file = tmpDir.appendingPathComponent("bad.txt")
        try "SECRET_KEY=hunter2".write(to: file, atomically: true, encoding: .utf8)

        let check = ExternalFileNotContainsCheck(
            name: "no secrets",
            section: "Security",
            path: file.path,
            pattern: "SECRET_KEY=",
            scope: .global,
            projectRoot: nil
        )
        let result = check.check()
        if case .fail = result {
            // expected
        } else {
            Issue.record("Expected .fail, got \(result)")
        }
    }

    @Test("File not contains check passes when file does not exist")
    func fileNotContainsMissingFile() {
        let check = ExternalFileNotContainsCheck(
            name: "no secrets",
            section: "Security",
            path: "/tmp/nonexistent-\(UUID().uuidString).txt",
            pattern: "SECRET_KEY=",
            scope: .global,
            projectRoot: nil
        )
        let result = check.check()
        if case .pass = result {
            // expected
        } else {
            Issue.record("Expected .pass, got \(result)")
        }
    }

    // MARK: - ExternalShellScriptCheck

    @Test("Shell script check passes with exit code 0")
    func shellScriptPass() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let script = tmpDir.appendingPathComponent("check.sh")
        try "#!/bin/bash\necho 'all good'\nexit 0".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let check = ExternalShellScriptCheck(
            name: "custom check",
            section: "Custom",
            scriptPath: script,
            packPath: tmpDir,
            fixScriptPath: nil,
            fixCommand: nil,
            scriptRunner: makeScriptRunner()
        )
        let result = check.check()
        if case .pass(let msg) = result {
            #expect(msg == "all good")
        } else {
            Issue.record("Expected .pass, got \(result)")
        }
    }

    @Test("Shell script check fails with exit code 1")
    func shellScriptFail() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let script = tmpDir.appendingPathComponent("check.sh")
        try "#!/bin/bash\necho 'something wrong'\nexit 1".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let check = ExternalShellScriptCheck(
            name: "custom check",
            section: "Custom",
            scriptPath: script,
            packPath: tmpDir,
            fixScriptPath: nil,
            fixCommand: nil,
            scriptRunner: makeScriptRunner()
        )
        let result = check.check()
        if case .fail(let msg) = result {
            #expect(msg == "something wrong")
        } else {
            Issue.record("Expected .fail, got \(result)")
        }
    }

    @Test("Shell script check warns with exit code 2")
    func shellScriptWarn() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let script = tmpDir.appendingPathComponent("check.sh")
        try "#!/bin/bash\necho 'heads up'\nexit 2".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let check = ExternalShellScriptCheck(
            name: "custom check",
            section: "Custom",
            scriptPath: script,
            packPath: tmpDir,
            fixScriptPath: nil,
            fixCommand: nil,
            scriptRunner: makeScriptRunner()
        )
        let result = check.check()
        if case .warn(let msg) = result {
            #expect(msg == "heads up")
        } else {
            Issue.record("Expected .warn, got \(result)")
        }
    }

    @Test("Shell script check skips with exit code 3")
    func shellScriptSkip() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let script = tmpDir.appendingPathComponent("check.sh")
        try "#!/bin/bash\necho 'not applicable'\nexit 3".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let check = ExternalShellScriptCheck(
            name: "custom check",
            section: "Custom",
            scriptPath: script,
            packPath: tmpDir,
            fixScriptPath: nil,
            fixCommand: nil,
            scriptRunner: makeScriptRunner()
        )
        let result = check.check()
        if case .skip(let msg) = result {
            #expect(msg == "not applicable")
        } else {
            Issue.record("Expected .skip, got \(result)")
        }
    }

    // MARK: - Factory

    @Test("Factory creates correct check type from definition")
    func factoryCreatesCorrectType() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let definition = ExternalDoctorCheckDefinition(
            type: .commandExists,
            name: "git check",
            section: "Dependencies",
            command: "git",
            args: ["--version"],
            path: nil,
            pattern: nil,
            scope: nil,
            fixCommand: nil,
            fixScript: nil
        )

        let check = ExternalDoctorCheckFactory.makeCheck(
            from: definition,
            packPath: tmpDir,
            projectRoot: nil,
            scriptRunner: makeScriptRunner()
        )

        #expect(check.name == "git check")
        #expect(check.section == "Dependencies")
    }

    @Test("Factory defaults section to 'External Pack' when nil")
    func factoryDefaultsSection() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let definition = ExternalDoctorCheckDefinition(
            type: .fileExists,
            name: "config file",
            section: nil,
            command: nil,
            args: nil,
            path: "/tmp/test.txt",
            pattern: nil,
            scope: nil,
            fixCommand: nil,
            fixScript: nil
        )

        let check = ExternalDoctorCheckFactory.makeCheck(
            from: definition,
            packPath: tmpDir,
            projectRoot: nil,
            scriptRunner: makeScriptRunner()
        )

        #expect(check.section == "External Pack")
    }
}

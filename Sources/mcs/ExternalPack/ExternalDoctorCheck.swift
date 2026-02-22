import Foundation

// MARK: - Command Exists Check

/// Checks that a command exists and is runnable with the given arguments.
struct ExternalCommandExistsCheck: DoctorCheck, Sendable {
    let name: String
    let section: String
    let command: String
    let args: [String]
    let fixCommand: String?

    func check() -> CheckResult {
        let shell = ShellRunner(environment: Environment())
        let result = shell.run(command, arguments: args)
        if result.succeeded {
            return .pass("available")
        }
        // Also try as a command name on PATH (not a full path)
        if shell.commandExists(command) {
            return .pass("installed")
        }
        return .fail("not found")
    }

    func fix() -> FixResult {
        guard let fixCommand else {
            return .notFixable("Run 'mcs install' to install dependencies")
        }
        let shell = ShellRunner(environment: Environment())
        let result = shell.shell(fixCommand)
        if result.succeeded {
            return .fixed("fix command succeeded")
        }
        return .failed(result.stderr)
    }
}

// MARK: - File Exists Check

/// Checks that a file exists at the given path.
struct ExternalFileExistsCheck: DoctorCheck, Sendable {
    let name: String
    let section: String
    let path: String
    let scope: ExternalDoctorCheckScope
    let projectRoot: URL?

    func check() -> CheckResult {
        guard let resolved = resolvePath() else {
            return .skip("no project root for project-scoped check")
        }
        if FileManager.default.fileExists(atPath: resolved) {
            return .pass("present")
        }
        return .fail("missing")
    }

    func fix() -> FixResult {
        .notFixable("Run 'mcs install' to install")
    }

    private func resolvePath() -> String? {
        switch scope {
        case .global:
            return expandTilde(path)
        case .project:
            guard let root = projectRoot else { return nil }
            return root.appendingPathComponent(path).path
        }
    }
}

// MARK: - Directory Exists Check

/// Checks that a directory exists at the given path.
struct ExternalDirectoryExistsCheck: DoctorCheck, Sendable {
    let name: String
    let section: String
    let path: String
    let scope: ExternalDoctorCheckScope
    let projectRoot: URL?

    func check() -> CheckResult {
        guard let resolved = resolvePath() else {
            return .skip("no project root for project-scoped check")
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue {
            return .pass("present")
        }
        return .fail("missing")
    }

    func fix() -> FixResult {
        .notFixable("Run 'mcs install' to install")
    }

    private func resolvePath() -> String? {
        switch scope {
        case .global:
            return expandTilde(path)
        case .project:
            guard let root = projectRoot else { return nil }
            return root.appendingPathComponent(path).path
        }
    }
}

// MARK: - File Contains Check

/// Checks that a file contains a given substring pattern.
struct ExternalFileContainsCheck: DoctorCheck, Sendable {
    let name: String
    let section: String
    let path: String
    let pattern: String
    let scope: ExternalDoctorCheckScope
    let projectRoot: URL?

    func check() -> CheckResult {
        guard let resolved = resolvePath() else {
            return .skip("no project root for project-scoped check")
        }
        guard let content = try? String(contentsOfFile: resolved, encoding: .utf8) else {
            return .fail("file not found or unreadable")
        }
        if content.contains(pattern) {
            return .pass("pattern found")
        }
        return .fail("pattern not found")
    }

    func fix() -> FixResult {
        .notFixable("Run 'mcs install' to fix")
    }

    private func resolvePath() -> String? {
        switch scope {
        case .global:
            return expandTilde(path)
        case .project:
            guard let root = projectRoot else { return nil }
            return root.appendingPathComponent(path).path
        }
    }
}

// MARK: - File Not Contains Check

/// Checks that a file does NOT contain a given substring pattern.
struct ExternalFileNotContainsCheck: DoctorCheck, Sendable {
    let name: String
    let section: String
    let path: String
    let pattern: String
    let scope: ExternalDoctorCheckScope
    let projectRoot: URL?

    func check() -> CheckResult {
        guard let resolved = resolvePath() else {
            return .skip("no project root for project-scoped check")
        }
        guard let content = try? String(contentsOfFile: resolved, encoding: .utf8) else {
            // File not found — pattern is not present, so this passes
            return .pass("file not present (pattern absent)")
        }
        if content.contains(pattern) {
            return .fail("unwanted pattern found")
        }
        return .pass("pattern absent")
    }

    func fix() -> FixResult {
        .notFixable("Run 'mcs install' to fix")
    }

    private func resolvePath() -> String? {
        switch scope {
        case .global:
            return expandTilde(path)
        case .project:
            guard let root = projectRoot else { return nil }
            return root.appendingPathComponent(path).path
        }
    }
}

// MARK: - Shell Script Check

/// Runs a custom shell script with exit code conventions:
/// - 0 = pass
/// - 1 = fail
/// - 2 = warn
/// - 3 = skip
/// stdout is used as the message.
struct ExternalShellScriptCheck: DoctorCheck, Sendable {
    let name: String
    let section: String
    let scriptPath: URL
    let packPath: URL
    let fixScriptPath: URL?
    let fixCommand: String?
    let scriptRunner: ScriptRunner

    func check() -> CheckResult {
        let result: ScriptRunner.ScriptResult
        do {
            result = try scriptRunner.run(script: scriptPath, packPath: packPath)
        } catch {
            return .fail(error.localizedDescription)
        }

        let message = result.stdout.isEmpty ? name : result.stdout

        switch result.exitCode {
        case 0:
            return .pass(message)
        case 1:
            return .fail(message)
        case 2:
            return .warn(message)
        case 3:
            return .skip(message)
        default:
            return .fail("unexpected exit code \(result.exitCode): \(message)")
        }
    }

    func fix() -> FixResult {
        if let fixScriptPath {
            do {
                let result = try scriptRunner.run(script: fixScriptPath, packPath: packPath)
                if result.succeeded {
                    let message = result.stdout.isEmpty ? "fix applied" : result.stdout
                    return .fixed(message)
                }
                let message = result.stderr.isEmpty ? result.stdout : result.stderr
                return .failed(message.isEmpty ? "fix script failed" : message)
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        if let fixCommand {
            let result = scriptRunner.runCommand(fixCommand)
            if result.succeeded {
                let message = result.stdout.isEmpty ? "fix applied" : result.stdout
                return .fixed(message)
            }
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            return .failed(message.isEmpty ? "fix command failed" : message)
        }

        return .notFixable("No fix available for this check")
    }
}

// MARK: - Factory

/// Creates concrete `DoctorCheck` instances from declarative `ExternalDoctorCheckDefinition`.
enum ExternalDoctorCheckFactory {
    /// Build a `DoctorCheck` from a declarative definition.
    ///
    /// - Parameters:
    ///   - definition: The declarative check from the manifest
    ///   - packPath: Root directory of the external pack
    ///   - projectRoot: Project root for project-scoped checks (nil if not in a project)
    ///   - scriptRunner: Runner for shell script checks
    static func makeCheck(
        from definition: ExternalDoctorCheckDefinition,
        packPath: URL,
        projectRoot: URL?,
        scriptRunner: ScriptRunner
    ) -> any DoctorCheck {
        let section = definition.section ?? "External Pack"
        let scope = definition.scope ?? .global

        switch definition.type {
        case .commandExists:
            return ExternalCommandExistsCheck(
                name: definition.name,
                section: section,
                command: definition.command ?? "",
                args: definition.args ?? [],
                fixCommand: definition.fixCommand
            )

        case .fileExists:
            return ExternalFileExistsCheck(
                name: definition.name,
                section: section,
                path: definition.path ?? "",
                scope: scope,
                projectRoot: projectRoot
            )

        case .directoryExists:
            return ExternalDirectoryExistsCheck(
                name: definition.name,
                section: section,
                path: definition.path ?? "",
                scope: scope,
                projectRoot: projectRoot
            )

        case .fileContains:
            return ExternalFileContainsCheck(
                name: definition.name,
                section: section,
                path: definition.path ?? "",
                pattern: definition.pattern ?? "",
                scope: scope,
                projectRoot: projectRoot
            )

        case .fileNotContains:
            return ExternalFileNotContainsCheck(
                name: definition.name,
                section: section,
                path: definition.path ?? "",
                pattern: definition.pattern ?? "",
                scope: scope,
                projectRoot: projectRoot
            )

        case .shellScript:
            let scriptURL: URL
            if let command = definition.command {
                scriptURL = packPath.appendingPathComponent(command)
            } else {
                scriptURL = packPath.appendingPathComponent("doctor-check.sh")
            }
            let fixURL: URL? = definition.fixScript.map {
                packPath.appendingPathComponent($0)
            }
            return ExternalShellScriptCheck(
                name: definition.name,
                section: section,
                scriptPath: scriptURL,
                packPath: packPath,
                fixScriptPath: fixURL,
                fixCommand: definition.fixCommand,
                scriptRunner: scriptRunner
            )
        }
    }
}

// MARK: - Helpers

/// Expand `~` at the start of a path to the user's home directory.
private func expandTilde(_ path: String) -> String {
    if path.hasPrefix("~/") {
        return NSString(string: path).expandingTildeInPath
    }
    return path
}

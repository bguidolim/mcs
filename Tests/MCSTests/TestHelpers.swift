import Foundation
@testable import mcs

/// Mock `ClaudeCLI` that records calls without executing real shell commands.
final class MockClaudeCLI: ClaudeCLI, @unchecked Sendable {
    struct MCPAddCall: Equatable {
        let name: String
        let scope: String
        let arguments: [String]
    }

    struct MCPRemoveCall: Equatable {
        let name: String
        let scope: String
    }

    struct PluginCall: Equatable {
        let name: String
    }

    var isAvailable: Bool {
        true
    }

    var mcpAddCalls: [MCPAddCall] = []
    var mcpRemoveCalls: [MCPRemoveCall] = []
    var pluginMarketplaceAddCalls: [String] = []
    var pluginInstallCalls: [PluginCall] = []
    var pluginRemoveCalls: [PluginCall] = []

    /// Result to return from all operations. Defaults to success.
    var result = ShellResult(exitCode: 0, stdout: "", stderr: "")

    @discardableResult
    func mcpAdd(name: String, scope: String, arguments: [String]) -> ShellResult {
        mcpAddCalls.append(MCPAddCall(name: name, scope: scope, arguments: arguments))
        return result
    }

    @discardableResult
    func mcpRemove(name: String, scope: String) -> ShellResult {
        mcpRemoveCalls.append(MCPRemoveCall(name: name, scope: scope))
        return result
    }

    @discardableResult
    func pluginMarketplaceAdd(repo: String) -> ShellResult {
        pluginMarketplaceAddCalls.append(repo)
        return result
    }

    @discardableResult
    func pluginInstall(ref: PluginRef) -> ShellResult {
        pluginInstallCalls.append(PluginCall(name: ref.bareName))
        return result
    }

    @discardableResult
    func pluginRemove(ref: PluginRef) -> ShellResult {
        pluginRemoveCalls.append(PluginCall(name: ref.bareName))
        return result
    }
}

/// Mock `ShellRunning` that records calls without executing real processes.
final class MockShellRunner: ShellRunning, @unchecked Sendable {
    struct RunCall: Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
        let additionalEnvironment: [String: String]
        let interactive: Bool
    }

    struct ShellCall: Equatable {
        let command: String
        let workingDirectory: String?
        let additionalEnvironment: [String: String]
        let interactive: Bool
    }

    let environment: Environment

    /// Lock around all mutable state. The mock is `@unchecked Sendable` and is invoked
    /// from `DispatchQueue.concurrentPerform` in `UpdateChecker.checkPackUpdates`, where
    /// multiple threads race on `runResults.removeFirst()` and `runCalls.append(...)`.
    /// The lock keeps both the queue and the call-recording array internally consistent.
    private let lock = NSLock()

    var runCalls: [RunCall] = []
    var shellCalls: [ShellCall] = []
    var commandExistsCalls: [String] = []

    /// Result returned from `run()` and `shell()`. Defaults to success.
    var result = ShellResult(exitCode: 0, stdout: "", stderr: "")

    /// Sequential results for `run()`: pops first element when non-empty, falls back to `result`.
    /// Positional ordering — only safe for tests where shell calls happen in a known order.
    /// For parallel tests where `concurrentPerform` may interleave calls, use
    /// `runResultsByFirstArg` instead (order-free, argument-keyed dispatch).
    var runResults: [ShellResult] = []

    /// Argument-keyed dispatch for `run()`. When `arguments.first` matches a key here,
    /// the mapped result is returned without consuming from `runResults`. Designed for
    /// tests that exercise `DispatchQueue.concurrentPerform` paths where positional
    /// ordering is non-deterministic — every ls-remote / fetch / diff call returns the
    /// same canned response regardless of which iteration emitted it.
    var runResultsByFirstArg: [String: ShellResult] = [:]

    /// Sequential results for `shell()`: pops first element when non-empty, falls back to `result`.
    var shellResults: [ShellResult] = []

    /// Controls what `commandExists()` returns. Defaults to `true`.
    var commandExistsResult = true

    init(environment: Environment = Environment()) {
        self.environment = environment
    }

    func commandExists(_ command: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        commandExistsCalls.append(command)
        return commandExistsResult
    }

    @discardableResult
    func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: String?,
        additionalEnvironment: [String: String],
        interactive: Bool
    ) -> ShellResult {
        lock.lock()
        defer { lock.unlock() }
        runCalls.append(RunCall(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            additionalEnvironment: additionalEnvironment,
            interactive: interactive
        ))
        if let firstArg = arguments.first, let scripted = runResultsByFirstArg[firstArg] {
            return scripted
        }
        if !runResults.isEmpty {
            return runResults.removeFirst()
        }
        return result
    }

    @discardableResult
    func shell(
        _ command: String,
        workingDirectory: String?,
        additionalEnvironment: [String: String],
        interactive: Bool
    ) -> ShellResult {
        lock.lock()
        defer { lock.unlock() }
        shellCalls.append(ShellCall(
            command: command,
            workingDirectory: workingDirectory,
            additionalEnvironment: additionalEnvironment,
            interactive: interactive
        ))
        if !shellResults.isEmpty {
            return shellResults.removeFirst()
        }
        return result
    }
}

/// Minimal TechPack implementation for tests.
struct MockTechPack: TechPack {
    let identifier: String
    let displayName: String
    let description: String = "Mock pack for testing"
    let components: [ComponentDefinition]
    let templates: [TemplateContribution]
    private let storedChecks: [any DoctorCheck]

    init(
        identifier: String,
        displayName: String,
        components: [ComponentDefinition] = [],
        templates: [TemplateContribution] = [],
        supplementaryDoctorChecks: [any DoctorCheck] = []
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.components = components
        self.templates = templates
        storedChecks = supplementaryDoctorChecks
    }

    func supplementaryDoctorChecks(projectRoot _: URL?) -> [any DoctorCheck] {
        storedChecks
    }

    func configureProject(at _: URL, context _: ProjectConfigContext) throws {}
}

/// Mock TechPack that declares prompts and resolves them using `context.priorValues`
/// (falling back to a `defaultAnswer` closure when no prior exists). Simulates the
/// adapter's "skip keys already in resolvedValues" filter so tests can verify the
/// full reuse pipeline without needing interactive stdin.
struct MockPromptTechPack: TechPack {
    let identifier: String
    let displayName: String
    let description: String = "Mock pack with prompts"
    let components: [ComponentDefinition]
    let templates: [TemplateContribution]
    private let prompts: [PromptDefinition]
    private let defaultAnswer: @Sendable (String) -> String

    init(
        identifier: String,
        displayName: String,
        prompts: [PromptDefinition],
        components: [ComponentDefinition] = [],
        templates: [TemplateContribution] = [],
        defaultAnswer: @escaping @Sendable (String) -> String = { "default-\($0)" }
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.prompts = prompts
        self.components = components
        self.templates = templates
        self.defaultAnswer = defaultAnswer
    }

    func supplementaryDoctorChecks(projectRoot _: URL?) -> [any DoctorCheck] {
        []
    }

    func declaredPrompts(context _: ProjectConfigContext) -> [PromptDefinition] {
        prompts
    }

    func templateValues(context: ProjectConfigContext) -> [String: String] {
        var resolved: [String: String] = [:]
        for prompt in prompts where context.resolvedValues[prompt.key] == nil {
            // Mirror real executor semantics: a select prior is only a valid answer
            // when it still matches one of the current options. Otherwise fall back
            // to the mock's defaultAnswer (simulating the user picking fresh).
            let prior = context.priorValues[prompt.key]
            if prompt.type == .select, let prior, let options = prompt.options,
               !options.contains(where: { $0.value == prior }) {
                resolved[prompt.key] = defaultAnswer(prompt.key)
            } else {
                resolved[prompt.key] = prior ?? defaultAnswer(prompt.key)
            }
        }
        return resolved
    }

    func configureProject(at _: URL, context _: ProjectConfigContext) throws {}
}

/// Mock TechPack that tracks `configureProject` invocations.
final class TrackingMockTechPack: TechPack, @unchecked Sendable {
    let identifier: String
    let displayName: String
    let description: String = "Tracking mock pack"
    let components: [ComponentDefinition]
    let templates: [TemplateContribution]
    var configureProjectCallCount = 0

    init(
        identifier: String,
        displayName: String,
        components: [ComponentDefinition] = [],
        templates: [TemplateContribution] = []
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.components = components
        self.templates = templates
    }

    func supplementaryDoctorChecks(projectRoot _: URL?) -> [any DoctorCheck] {
        []
    }

    func configureProject(at _: URL, context _: ProjectConfigContext) throws {
        configureProjectCallCount += 1
    }
}

// MARK: - PackEntry Factories

/// Create a `PackRegistryFile.PackEntry` for tests.
func makeRegistryEntry(
    identifier: String,
    commitSHA: String = "abc123def456",
    sourceURL: String? = nil
) -> PackRegistryFile.PackEntry {
    PackRegistryFile.PackEntry(
        identifier: identifier,
        displayName: identifier,
        author: nil,
        sourceURL: sourceURL ?? "https://example.com/\(identifier).git",
        ref: nil,
        commitSHA: commitSHA,
        localPath: identifier,
        addedAt: "2026-01-01T00:00:00Z",
        trustedScriptHashes: [:],
        isLocal: nil
    )
}

/// Create a local `PackRegistryFile.PackEntry` for tests.
func makeLocalRegistryEntry(
    identifier: String,
    localPath: String = "/Users/dev/local-pack"
) -> PackRegistryFile.PackEntry {
    PackRegistryFile.PackEntry(
        identifier: identifier,
        displayName: identifier,
        author: nil,
        sourceURL: localPath,
        ref: nil,
        commitSHA: "local",
        localPath: localPath,
        addedAt: "2026-01-01T00:00:00Z",
        trustedScriptHashes: [:],
        isLocal: true
    )
}

/// Create the on-disk pack clone directory at `<home>/.mcs/packs/<identifier>/` so
/// `PackEntry.resolvedPath(packsDirectory:)` succeeds and the path-containment check
/// inside it doesn't fail. The directory is empty — tests that mock the shell don't
/// need a real git checkout, only a valid working directory to pass to git invocations.
func preparePackDir(home: URL, identifier: String) throws {
    let dir = home.appendingPathComponent(".mcs/packs/\(identifier)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

// MARK: - Temp Directory Helpers

/// Create a bare temp directory with a UUID-unique name.
func makeTmpDir(label: String = "test") throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mcs-\(label)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Create a temp directory pre-configured for global-scope tests (`.claude/` + `.mcs/` subdirectories).
func makeGlobalTmpDir(label: String = "global") throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mcs-\(label)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: dir.appendingPathComponent(Constants.FileNames.claudeDirectory),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: dir.appendingPathComponent(".mcs"),
        withIntermediateDirectories: true
    )
    return dir
}

/// Create a temp home pre-configured with the Claude Code canonical layout:
/// `.claude/` directory plus (optional) `.claude.json` sibling file.
func makeClaudeHome(label: String = "claude-home", withJSON: Bool = true) throws -> URL {
    let home = try makeGlobalTmpDir(label: label)
    if withJSON {
        try "{}".write(
            to: home.appendingPathComponent(".claude.json"),
            atomically: true, encoding: .utf8
        )
    }
    return home
}

/// Create a temp directory pre-configured as a project sandbox:
/// home with `.claude/` + `.mcs/`, plus a nested project with `.git/` + `.claude/`.
func makeSandboxProject(label: String = "project") throws -> (home: URL, project: URL) {
    let home = try makeGlobalTmpDir(label: label)
    let project = home.appendingPathComponent("test-project")
    try FileManager.default.createDirectory(
        at: project.appendingPathComponent(".git"),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: project.appendingPathComponent(Constants.FileNames.claudeDirectory),
        withIntermediateDirectories: true
    )
    return (home, project)
}

/// Create a `Configurator` configured for global-scope sync.
func makeGlobalSyncConfigurator(
    home: URL,
    mockCLI: MockClaudeCLI = MockClaudeCLI(),
    shell: (any ShellRunning)? = nil
) -> Configurator {
    let env = Environment(home: home)
    return Configurator(
        environment: env,
        output: CLIOutput(colorsEnabled: false),
        shell: shell ?? ShellRunner(environment: env),
        strategy: GlobalSyncStrategy(environment: env),
        claudeCLI: mockCLI
    )
}

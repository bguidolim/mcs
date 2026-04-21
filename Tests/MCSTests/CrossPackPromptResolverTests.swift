import Foundation
@testable import mcs
import Testing

struct CrossPackPromptResolverTests {
    // MARK: - Helpers

    private func makeContext() -> ProjectConfigContext {
        ProjectConfigContext(
            projectPath: FileManager.default.temporaryDirectory,
            repoName: "test-repo",
            output: CLIOutput(colorsEnabled: false),
            resolvedValues: [:],
            isGlobalScope: false
        )
    }

    private func makeMockPack(
        name: String,
        prompts: [PromptDefinition]
    ) -> PromptMockPack {
        PromptMockPack(
            identifier: name,
            displayName: name,
            prompts: prompts
        )
    }

    // MARK: - Grouping

    @Test("Groups input prompts with the same key across packs")
    func groupsInputPrompts() {
        let packA = makeMockPack(name: "pack-a", prompts: [
            PromptDefinition(
                key: "BRANCH_PREFIX", type: .input,
                label: "Branch prefix from A", defaultValue: "feature",
                options: nil, detectPatterns: nil, scriptCommand: nil
            ),
        ])
        let packB = makeMockPack(name: "pack-b", prompts: [
            PromptDefinition(
                key: "BRANCH_PREFIX", type: .input,
                label: "Branch prefix from B", defaultValue: "feat",
                options: nil, detectPatterns: nil, scriptCommand: nil
            ),
        ])

        let context = makeContext()
        let shared = CrossPackPromptResolver.groupSharedPrompts(packs: [packA, packB], context: context)

        #expect(shared.count == 1)
        #expect(shared["BRANCH_PREFIX"]?.count == 2)
        #expect(shared["BRANCH_PREFIX"]?[0].packName == "pack-a")
        #expect(shared["BRANCH_PREFIX"]?[1].packName == "pack-b")
    }

    @Test("Groups select prompts with the same key across packs")
    func groupsSelectPrompts() {
        let packA = makeMockPack(name: "pack-a", prompts: [
            PromptDefinition(
                key: "PLATFORM", type: .select,
                label: "Target platform", defaultValue: nil,
                options: [PromptOption(value: "ios", label: "iOS")],
                detectPatterns: nil, scriptCommand: nil
            ),
        ])
        let packB = makeMockPack(name: "pack-b", prompts: [
            PromptDefinition(
                key: "PLATFORM", type: .select,
                label: "Platform for B", defaultValue: nil,
                options: [PromptOption(value: "macos", label: "macOS")],
                detectPatterns: nil, scriptCommand: nil
            ),
        ])

        let context = makeContext()
        let shared = CrossPackPromptResolver.groupSharedPrompts(packs: [packA, packB], context: context)

        #expect(shared.count == 1)
        #expect(shared["PLATFORM"]?.count == 2)
    }

    @Test("Single-pack prompts are not grouped as shared")
    func singlePackNotShared() {
        let packA = makeMockPack(name: "pack-a", prompts: [
            PromptDefinition(
                key: "UNIQUE_KEY", type: .input,
                label: "Only in A", defaultValue: nil,
                options: nil, detectPatterns: nil, scriptCommand: nil
            ),
        ])
        let packB = makeMockPack(name: "pack-b", prompts: [
            PromptDefinition(
                key: "OTHER_KEY", type: .input,
                label: "Only in B", defaultValue: nil,
                options: nil, detectPatterns: nil, scriptCommand: nil
            ),
        ])

        let context = makeContext()
        let shared = CrossPackPromptResolver.groupSharedPrompts(packs: [packA, packB], context: context)

        #expect(shared.isEmpty)
    }

    @Test("script prompts are excluded from deduplication")
    func scriptExcluded() {
        let packA = makeMockPack(name: "pack-a", prompts: [
            PromptDefinition(
                key: "BRANCH", type: .script,
                label: nil, defaultValue: nil,
                options: nil, detectPatterns: nil, scriptCommand: "git branch"
            ),
        ])
        let packB = makeMockPack(name: "pack-b", prompts: [
            PromptDefinition(
                key: "BRANCH", type: .script,
                label: nil, defaultValue: nil,
                options: nil, detectPatterns: nil, scriptCommand: "echo main"
            ),
        ])

        let context = makeContext()
        let shared = CrossPackPromptResolver.groupSharedPrompts(packs: [packA, packB], context: context)

        #expect(shared.isEmpty)
    }

    @Test("fileDetect prompts are excluded from deduplication")
    func fileDetectExcluded() {
        let packA = makeMockPack(name: "pack-a", prompts: [
            PromptDefinition(
                key: "PROJECT", type: .fileDetect,
                label: "Xcode project", defaultValue: nil,
                options: nil, detectPatterns: ["*.xcodeproj"], scriptCommand: nil
            ),
        ])
        let packB = makeMockPack(name: "pack-b", prompts: [
            PromptDefinition(
                key: "PROJECT", type: .fileDetect,
                label: "Project file", defaultValue: nil,
                options: nil, detectPatterns: ["*.xcworkspace"], scriptCommand: nil
            ),
        ])

        let context = makeContext()
        let shared = CrossPackPromptResolver.groupSharedPrompts(packs: [packA, packB], context: context)

        #expect(shared.isEmpty)
    }

    @Test("Three packs sharing a key produces a group of 3")
    func threePacksShared() {
        let packs = (1 ... 3).map { i in
            makeMockPack(name: "pack-\(i)", prompts: [
                PromptDefinition(
                    key: "SHARED", type: .input,
                    label: "Pack \(i) label", defaultValue: nil,
                    options: nil, detectPatterns: nil, scriptCommand: nil
                ),
            ])
        }

        let context = makeContext()
        let shared = CrossPackPromptResolver.groupSharedPrompts(packs: packs, context: context)

        #expect(shared["SHARED"]?.count == 3)
    }

    @Test("Mixed types across packs: only deduplicable types are grouped")
    func mixedTypes() {
        let packA = makeMockPack(name: "pack-a", prompts: [
            PromptDefinition(
                key: "VAL", type: .input,
                label: "Input A", defaultValue: nil,
                options: nil, detectPatterns: nil, scriptCommand: nil
            ),
            PromptDefinition(
                key: "DETECT", type: .fileDetect,
                label: "Detect A", defaultValue: nil,
                options: nil, detectPatterns: ["*.txt"], scriptCommand: nil
            ),
        ])
        let packB = makeMockPack(name: "pack-b", prompts: [
            PromptDefinition(
                key: "VAL", type: .input,
                label: "Input B", defaultValue: nil,
                options: nil, detectPatterns: nil, scriptCommand: nil
            ),
            PromptDefinition(
                key: "DETECT", type: .fileDetect,
                label: "Detect B", defaultValue: nil,
                options: nil, detectPatterns: ["*.md"], scriptCommand: nil
            ),
        ])

        let context = makeContext()
        let shared = CrossPackPromptResolver.groupSharedPrompts(packs: [packA, packB], context: context)

        #expect(shared.count == 1)
        #expect(shared["VAL"] != nil)
        #expect(shared["DETECT"] == nil)
    }

    @Test("Skips keys that are already in context.resolvedValues")
    func skipsAlreadyResolvedKeys() {
        let packA = makeMockPack(name: "pack-a", prompts: [
            PromptDefinition(
                key: "BRANCH_PREFIX", type: .input,
                label: "Prefix from A", defaultValue: nil,
                options: nil, detectPatterns: nil, scriptCommand: nil
            ),
        ])
        let packB = makeMockPack(name: "pack-b", prompts: [
            PromptDefinition(
                key: "BRANCH_PREFIX", type: .input,
                label: "Prefix from B", defaultValue: nil,
                options: nil, detectPatterns: nil, scriptCommand: nil
            ),
        ])

        let context = ProjectConfigContext(
            projectPath: FileManager.default.temporaryDirectory,
            repoName: "test-repo",
            output: CLIOutput(colorsEnabled: false),
            resolvedValues: ["BRANCH_PREFIX": "feature"],
            isGlobalScope: false
        )
        let shared = CrossPackPromptResolver.groupSharedPrompts(packs: [packA, packB], context: context)

        // BRANCH_PREFIX is already resolved — should NOT appear in shared prompts
        #expect(shared.isEmpty)
    }

    @Test("Global scope filters out fileDetect from declaredPrompts")
    func globalScopeFiltersFileDetect() {
        let manifest = ExternalPackManifest(
            schemaVersion: 1,
            identifier: "test-pack",
            displayName: "Test",
            description: "Test",
            author: nil,
            minMCSVersion: nil,
            components: [],
            templates: nil,
            prompts: [
                PromptDefinition(
                    key: "PROJECT", type: .fileDetect,
                    label: "Xcode project", defaultValue: nil,
                    options: nil, detectPatterns: ["*.xcodeproj"], scriptCommand: nil
                ),
                PromptDefinition(
                    key: "PREFIX", type: .input,
                    label: "Branch prefix", defaultValue: "feature",
                    options: nil, detectPatterns: nil, scriptCommand: nil
                ),
            ],
            configureProject: nil,
            supplementaryDoctorChecks: nil
        )
        let adapter = ExternalPackAdapter(
            manifest: manifest,
            packPath: FileManager.default.temporaryDirectory
        )

        let globalContext = ProjectConfigContext(
            projectPath: FileManager.default.temporaryDirectory,
            repoName: "test",
            output: CLIOutput(colorsEnabled: false),
            resolvedValues: [:],
            isGlobalScope: true
        )

        let prompts = adapter.declaredPrompts(context: globalContext)
        #expect(prompts.count == 1)
        #expect(prompts[0].key == "PREFIX")
    }
}

// MARK: - MCPServerConfig substitution

struct MCPServerConfigSubstitutionTests {
    @Test("Substitutes env values")
    func substitutesEnv() {
        let config = MCPServerConfig(
            name: "test-server",
            command: "npx",
            args: ["-y", "server@latest"],
            env: ["API_KEY": "__USER_API_KEY__", "TOKEN": "__SERVICE_TOKEN__"]
        )
        let result = config.substituting(["USER_API_KEY": "abc123", "SERVICE_TOKEN": "tok456"])

        #expect(result.env["API_KEY"] == "abc123")
        #expect(result.env["TOKEN"] == "tok456")
    }

    @Test("Substitutes command and args")
    func substitutesCommandArgs() {
        let config = MCPServerConfig(
            name: "test-server",
            command: "__CMD__",
            args: ["--url", "__SERVER_URL__"],
            env: [:]
        )
        let result = config.substituting(["CMD": "uvx", "SERVER_URL": "https://example.com"])

        #expect(result.command == "uvx")
        #expect(result.args == ["--url", "https://example.com"])
    }

    @Test("Preserves name during substitution")
    func preservesName() {
        let config = MCPServerConfig(
            name: "__NAME__",
            command: "cmd",
            args: [],
            env: [:]
        )
        let result = config.substituting(["NAME": "should-not-change"])

        // Name contains __NAME__ literally because substituting() preserves name
        #expect(result.name == "__NAME__")
    }

    @Test("Empty values returns same config")
    func emptyValuesNoOp() {
        let config = MCPServerConfig(
            name: "server",
            command: "cmd",
            args: ["--flag"],
            env: ["KEY": "__PLACEHOLDER__"]
        )
        let result = config.substituting([:])

        #expect(result.env["KEY"] == "__PLACEHOLDER__")
        #expect(result.command == "cmd")
    }

    @Test("Preserves scope during substitution")
    func preservesScope() {
        let config = MCPServerConfig(
            name: "server",
            command: "cmd",
            args: [],
            env: [:],
            scope: "project"
        )
        let result = config.substituting(["FOO": "bar"])

        #expect(result.scope == "project")
    }
}

// MARK: - Settings load with substitution

struct SettingsLoadSubstitutionTests {
    private func makeTmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-settings-sub-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Substitutes placeholders in settings JSON before parsing")
    func substitutesBeforeParsing() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let settingsJSON = """
        {
            "env": {
                "API_KEY": "__USER_API_KEY__",
                "STATIC": "unchanged"
            }
        }
        """
        let url = tmpDir.appendingPathComponent("settings.json")
        try settingsJSON.write(to: url, atomically: true, encoding: .utf8)

        let settings = try Settings.load(from: url, substituting: ["USER_API_KEY": "secret123"])

        let envData = try #require(settings.extraJSON["env"])
        let env = try #require(JSONSerialization.jsonObject(with: envData) as? [String: String])
        #expect(env["API_KEY"] == "secret123")
        #expect(env["STATIC"] == "unchanged")
    }

    @Test("Empty values falls back to normal load")
    func emptyValuesFallsBack() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let settingsJSON = """
        {
            "env": {
                "KEY": "__PLACEHOLDER__"
            }
        }
        """
        let url = tmpDir.appendingPathComponent("settings.json")
        try settingsJSON.write(to: url, atomically: true, encoding: .utf8)

        let settings = try Settings.load(from: url, substituting: [:])

        let envData = try #require(settings.extraJSON["env"])
        let env = try #require(JSONSerialization.jsonObject(with: envData) as? [String: String])
        #expect(env["KEY"] == "__PLACEHOLDER__")
    }

    @Test("JSON-escapes values containing quotes and backslashes")
    func jsonEscapesSpecialCharacters() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let settingsJSON = """
        {
            "env": {
                "PATH_VAR": "__SOME_PATH__"
            }
        }
        """
        let url = tmpDir.appendingPathComponent("settings.json")
        try settingsJSON.write(to: url, atomically: true, encoding: .utf8)

        // Value with quotes and backslashes that would break JSON if not escaped
        let settings = try Settings.load(
            from: url,
            substituting: ["SOME_PATH": #"C:\Users\me "quoted""#]
        )

        let envData = try #require(settings.extraJSON["env"])
        let env = try #require(JSONSerialization.jsonObject(with: envData) as? [String: String])
        #expect(env["PATH_VAR"] == #"C:\Users\me "quoted""#)
    }

    @Test("Missing file returns empty settings")
    func missingFileReturnsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).json")

        let settings = try Settings.load(from: url, substituting: ["FOO": "bar"])

        #expect(settings.hooks == nil)
        #expect(settings.enabledPlugins == nil)
        #expect(settings.extraJSON.isEmpty)
    }
}

// MARK: - Undeclared placeholder scanner extension

struct ScannerExtensionTests {
    @Test("Finds placeholders in settings file sources")
    func findsSettingsPlaceholders() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-scan-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let settingsJSON = """
        {
            "env": {
                "API_KEY": "__MY_API_KEY__"
            }
        }
        """
        let url = tmpDir.appendingPathComponent("settings.json")
        try settingsJSON.write(to: url, atomically: true, encoding: .utf8)

        let pack = PromptMockPack(
            identifier: "test-pack",
            displayName: "Test",
            components: [ComponentDefinition(
                id: "test-pack.settings",
                displayName: "Settings",
                description: "Test",
                type: .configuration,
                packIdentifier: "test-pack",
                dependencies: [],
                isRequired: true,
                installAction: .settingsMerge(source: url)
            )]
        )

        let undeclared = ConfiguratorSupport.scanForUndeclaredPlaceholders(
            packs: [pack], resolvedValues: [:]
        )

        #expect(undeclared.contains("MY_API_KEY"))
    }

    @Test("Finds placeholders in MCP server env values")
    func findsMCPEnvPlaceholders() {
        let pack = PromptMockPack(
            identifier: "test-pack",
            displayName: "Test",
            components: [ComponentDefinition(
                id: "test-pack.mcp",
                displayName: "MCP Server",
                description: "Test",
                type: .mcpServer,
                packIdentifier: "test-pack",
                dependencies: [],
                isRequired: true,
                installAction: .mcpServer(MCPServerConfig(
                    name: "test",
                    command: "npx",
                    args: ["-y", "server"],
                    env: ["TOKEN": "__SERVICE_TOKEN__"]
                ))
            )]
        )

        let undeclared = ConfiguratorSupport.scanForUndeclaredPlaceholders(
            packs: [pack], resolvedValues: [:]
        )

        #expect(undeclared.contains("SERVICE_TOKEN"))
    }

    @Test("Finds placeholders in MCP server command")
    func findsMCPCommandPlaceholders() {
        let pack = PromptMockPack(
            identifier: "test-pack",
            displayName: "Test",
            components: [ComponentDefinition(
                id: "test-pack.mcp",
                displayName: "MCP Server",
                description: "Test",
                type: .mcpServer,
                packIdentifier: "test-pack",
                dependencies: [],
                isRequired: true,
                installAction: .mcpServer(MCPServerConfig(
                    name: "test",
                    command: "__MY_CMD__",
                    args: [],
                    env: [:]
                ))
            )]
        )

        let undeclared = ConfiguratorSupport.scanForUndeclaredPlaceholders(
            packs: [pack], resolvedValues: [:]
        )

        #expect(undeclared.contains("MY_CMD"))
    }

    @Test("Finds placeholders in MCP server args")
    func findsMCPArgPlaceholders() {
        let pack = PromptMockPack(
            identifier: "test-pack",
            displayName: "Test",
            components: [ComponentDefinition(
                id: "test-pack.mcp",
                displayName: "MCP Server",
                description: "Test",
                type: .mcpServer,
                packIdentifier: "test-pack",
                dependencies: [],
                isRequired: true,
                installAction: .mcpServer(MCPServerConfig(
                    name: "test",
                    command: "npx",
                    args: ["--endpoint", "__API_ENDPOINT__"],
                    env: [:]
                ))
            )]
        )

        let undeclared = ConfiguratorSupport.scanForUndeclaredPlaceholders(
            packs: [pack], resolvedValues: [:]
        )

        #expect(undeclared.contains("API_ENDPOINT"))
    }

    @Test("Already-resolved keys are not reported as undeclared")
    func resolvedKeysExcluded() {
        let pack = PromptMockPack(
            identifier: "test-pack",
            displayName: "Test",
            components: [ComponentDefinition(
                id: "test-pack.mcp",
                displayName: "MCP Server",
                description: "Test",
                type: .mcpServer,
                packIdentifier: "test-pack",
                dependencies: [],
                isRequired: true,
                installAction: .mcpServer(MCPServerConfig(
                    name: "test",
                    command: "npx",
                    args: [],
                    env: ["TOKEN": "__SERVICE_TOKEN__"]
                ))
            )]
        )

        let undeclared = ConfiguratorSupport.scanForUndeclaredPlaceholders(
            packs: [pack], resolvedValues: ["SERVICE_TOKEN": "already-resolved"]
        )

        #expect(!undeclared.contains("SERVICE_TOKEN"))
    }
}

// MARK: - partitionDeclaredPrompts

struct PartitionDeclaredPromptsTests {
    @Test("partition: input prompt with prior becomes reusable")
    func partitionInputPriorReusable() {
        let prompt = PromptDefinition(
            key: "BRANCH_PREFIX", type: .input,
            label: nil, defaultValue: nil, options: nil,
            detectPatterns: nil, scriptCommand: nil
        )
        let (reusable, newKeys) = CrossPackPromptResolver.partitionDeclaredPrompts(
            [prompt], priorValues: ["BRANCH_PREFIX": "bruno"]
        )
        #expect(reusable == ["BRANCH_PREFIX": "bruno"])
        #expect(newKeys.isEmpty)
    }

    @Test("partition: input prompt without prior becomes newDeclared")
    func partitionInputMissingPriorIsNew() {
        let prompt = PromptDefinition(
            key: "NEW_KEY", type: .input,
            label: nil, defaultValue: nil, options: nil,
            detectPatterns: nil, scriptCommand: nil
        )
        let (reusable, newKeys) = CrossPackPromptResolver.partitionDeclaredPrompts(
            [prompt], priorValues: [:]
        )
        #expect(reusable.isEmpty)
        #expect(newKeys == ["NEW_KEY"])
    }

    @Test("partition: select prompt with valid prior is reusable")
    func partitionSelectValidPriorReusable() {
        let prompt = PromptDefinition(
            key: "LOG_LEVEL", type: .select,
            label: nil, defaultValue: nil,
            options: [
                PromptOption(value: "info", label: "Info"),
                PromptOption(value: "debug", label: "Debug"),
            ],
            detectPatterns: nil, scriptCommand: nil
        )
        let (reusable, newKeys) = CrossPackPromptResolver.partitionDeclaredPrompts(
            [prompt], priorValues: ["LOG_LEVEL": "debug"]
        )
        #expect(reusable == ["LOG_LEVEL": "debug"])
        #expect(newKeys.isEmpty)
    }

    @Test("partition: select prompt with invalidated prior becomes newDeclared")
    func partitionSelectInvalidatedPriorIsNew() {
        let prompt = PromptDefinition(
            key: "LOG_LEVEL", type: .select,
            label: nil, defaultValue: nil,
            options: [
                PromptOption(value: "info", label: "Info"),
                PromptOption(value: "debug", label: "Debug"),
            ],
            detectPatterns: nil, scriptCommand: nil
        )
        let (reusable, newKeys) = CrossPackPromptResolver.partitionDeclaredPrompts(
            [prompt], priorValues: ["LOG_LEVEL": "trace-removed"]
        )
        #expect(reusable.isEmpty)
        #expect(newKeys == ["LOG_LEVEL"])
    }

    @Test("partition: select with valid option from any declaring pack is reusable")
    func partitionSelectAcrossPacksMergedOptions() {
        let fromPackA = PromptDefinition(
            key: "REGION", type: .select,
            label: nil, defaultValue: nil,
            options: [PromptOption(value: "us", label: "US")],
            detectPatterns: nil, scriptCommand: nil
        )
        let fromPackB = PromptDefinition(
            key: "REGION", type: .select,
            label: nil, defaultValue: nil,
            options: [PromptOption(value: "eu", label: "EU")],
            detectPatterns: nil, scriptCommand: nil
        )
        let (reusable, newKeys) = CrossPackPromptResolver.partitionDeclaredPrompts(
            [fromPackA, fromPackB], priorValues: ["REGION": "eu"]
        )
        #expect(reusable == ["REGION": "eu"])
        #expect(newKeys.isEmpty)
    }

    @Test("partition: select with nil options treats any prior as reusable (matches executor fallback)")
    func partitionSelectNilOptionsReusable() {
        let prompt = PromptDefinition(
            key: "FREEFORM", type: .select,
            label: nil, defaultValue: nil,
            options: nil,
            detectPatterns: nil, scriptCommand: nil
        )
        let (reusable, newKeys) = CrossPackPromptResolver.partitionDeclaredPrompts(
            [prompt], priorValues: ["FREEFORM": "anything"]
        )
        #expect(reusable == ["FREEFORM": "anything"])
        #expect(newKeys.isEmpty)
    }

    @Test("partition: select with empty options array treats any prior as reusable")
    func partitionSelectEmptyOptionsReusable() {
        let prompt = PromptDefinition(
            key: "FREEFORM", type: .select,
            label: nil, defaultValue: nil,
            options: [],
            detectPatterns: nil, scriptCommand: nil
        )
        let (reusable, _) = CrossPackPromptResolver.partitionDeclaredPrompts(
            [prompt], priorValues: ["FREEFORM": "anything"]
        )
        #expect(reusable == ["FREEFORM": "anything"])
    }

    @Test("partition: mixed constrained + unconstrained — prior outside constraints is not reusable")
    func partitionMixedConstrainedRejectsOutOfConstraint() {
        // Pack A restricts REGION to [us]; pack B declares REGION select with nil options.
        // The shared resolver would present [us] to the user, so a prior of "zz" must be re-asked.
        let constrained = PromptDefinition(
            key: "REGION", type: .select,
            label: nil, defaultValue: nil,
            options: [PromptOption(value: "us", label: "US")],
            detectPatterns: nil, scriptCommand: nil
        )
        let unconstrained = PromptDefinition(
            key: "REGION", type: .select,
            label: nil, defaultValue: nil,
            options: nil,
            detectPatterns: nil, scriptCommand: nil
        )
        let (reusable, newKeys) = CrossPackPromptResolver.partitionDeclaredPrompts(
            [constrained, unconstrained], priorValues: ["REGION": "zz"]
        )
        #expect(reusable.isEmpty)
        #expect(newKeys == ["REGION"])
    }

    @Test("partition: mixed constrained + unconstrained — prior inside constraints is reusable")
    func partitionMixedConstrainedAcceptsValidValue() {
        let constrained = PromptDefinition(
            key: "REGION", type: .select,
            label: nil, defaultValue: nil,
            options: [PromptOption(value: "us", label: "US")],
            detectPatterns: nil, scriptCommand: nil
        )
        let unconstrained = PromptDefinition(
            key: "REGION", type: .select,
            label: nil, defaultValue: nil,
            options: nil,
            detectPatterns: nil, scriptCommand: nil
        )
        let (reusable, _) = CrossPackPromptResolver.partitionDeclaredPrompts(
            [constrained, unconstrained], priorValues: ["REGION": "us"]
        )
        #expect(reusable == ["REGION": "us"])
    }

    @Test("collectDeclaredPrompts preserves duplicate-key declarations across packs")
    func collectPreservesPerPackDeclarations() {
        let packA = PromptMockPack(
            identifier: "pack-a", displayName: "A",
            prompts: [PromptDefinition(
                key: "REGION", type: .select,
                label: nil, defaultValue: nil,
                options: [PromptOption(value: "us", label: "US")],
                detectPatterns: nil, scriptCommand: nil
            )]
        )
        let packB = PromptMockPack(
            identifier: "pack-b", displayName: "B",
            prompts: [PromptDefinition(
                key: "REGION", type: .select,
                label: nil, defaultValue: nil,
                options: [PromptOption(value: "eu", label: "EU")],
                detectPatterns: nil, scriptCommand: nil
            )]
        )
        let context = ProjectConfigContext(
            projectPath: URL(fileURLWithPath: "/tmp"),
            repoName: "",
            output: CLIOutput(colorsEnabled: false)
        )

        let collected = CrossPackPromptResolver.collectDeclaredPrompts(
            packs: [packA, packB], context: context
        )
        #expect(collected.count == 2)

        // Downstream partition sees both declarations → "eu" from pack B validates.
        let (reusable, newKeys) = CrossPackPromptResolver.partitionDeclaredPrompts(
            collected, priorValues: ["REGION": "eu"]
        )
        #expect(reusable == ["REGION": "eu"])
        #expect(newKeys.isEmpty)
    }

    @Test("partition: script prompt is neither reusable nor newDeclared")
    func partitionScriptExcluded() {
        let prompt = PromptDefinition(
            key: "VERSION", type: .script,
            label: nil, defaultValue: nil, options: nil,
            detectPatterns: nil, scriptCommand: "echo 1.0"
        )
        let (reusable, newKeys) = CrossPackPromptResolver.partitionDeclaredPrompts(
            [prompt], priorValues: ["VERSION": "0.9"]
        )
        #expect(reusable.isEmpty)
        #expect(newKeys.isEmpty)
    }

    @Test("partition: fileDetect prompt is neither reusable nor newDeclared")
    func partitionFileDetectExcluded() {
        let prompt = PromptDefinition(
            key: "PROJECT", type: .fileDetect,
            label: nil, defaultValue: nil, options: nil,
            detectPatterns: ["*.xcodeproj"], scriptCommand: nil
        )
        let (reusable, newKeys) = CrossPackPromptResolver.partitionDeclaredPrompts(
            [prompt], priorValues: ["PROJECT": "App.xcodeproj"]
        )
        #expect(reusable.isEmpty)
        #expect(newKeys.isEmpty)
    }

    @Test("partition: type conflict falls back to input reuse semantics")
    func partitionTypeConflictFallsBackToInput() {
        let asInput = PromptDefinition(
            key: "SHARED", type: .input,
            label: nil, defaultValue: nil, options: nil,
            detectPatterns: nil, scriptCommand: nil
        )
        let asSelect = PromptDefinition(
            key: "SHARED", type: .select,
            label: nil, defaultValue: nil,
            options: [PromptOption(value: "a", label: "A")],
            detectPatterns: nil, scriptCommand: nil
        )
        let (reusable, newKeys) = CrossPackPromptResolver.partitionDeclaredPrompts(
            [asInput, asSelect], priorValues: ["SHARED": "anything"]
        )
        #expect(reusable == ["SHARED": "anything"])
        #expect(newKeys.isEmpty)
    }
}

// MARK: - PromptMockPack

/// A mock TechPack that supports declaredPrompts for testing cross-pack dedup.
private struct PromptMockPack: TechPack {
    let identifier: String
    let displayName: String
    let description: String = "Mock pack for prompt tests"
    let components: [ComponentDefinition]
    let templates: [TemplateContribution] = []
    func supplementaryDoctorChecks(projectRoot _: URL?) -> [any DoctorCheck] {
        []
    }

    private let prompts: [PromptDefinition]

    init(
        identifier: String,
        displayName: String,
        prompts: [PromptDefinition] = [],
        components: [ComponentDefinition] = []
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.prompts = prompts
        self.components = components
    }

    func configureProject(at _: URL, context _: ProjectConfigContext) throws {}

    func declaredPrompts(context: ProjectConfigContext) -> [PromptDefinition] {
        context.isGlobalScope
            ? prompts.filter { $0.type != .fileDetect }
            : prompts
    }
}

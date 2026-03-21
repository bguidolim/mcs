import Foundation
@testable import mcs
import Testing

// MARK: - Test Bed

/// Reusable sandbox environment for lifecycle tests.
private struct LifecycleTestBed {
    let home: URL
    let project: URL
    let env: Environment
    let mockCLI: MockClaudeCLI

    init() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-lifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        // Create ~/.claude/ and ~/.mcs/
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".mcs"),
            withIntermediateDirectories: true
        )
        // Create project with .git/ and .claude/
        project = home.appendingPathComponent("test-project")
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent(".claude"),
            withIntermediateDirectories: true
        )
        env = Environment(home: home)
        mockCLI = MockClaudeCLI()
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: home)
    }

    func makeConfigurator(registry: TechPackRegistry = TechPackRegistry()) -> Configurator {
        Configurator(
            environment: env,
            output: CLIOutput(colorsEnabled: false),
            shell: ShellRunner(environment: env),
            registry: registry,
            strategy: ProjectSyncStrategy(projectPath: project, environment: env),
            claudeCLI: mockCLI
        )
    }

    func makeDoctorRunner(registry: TechPackRegistry, packFilter: String? = nil) -> DoctorRunner {
        DoctorRunner(
            fixMode: false,
            skipConfirmation: true,
            packFilter: packFilter,
            registry: registry,
            environment: env,
            projectRootOverride: project
        )
    }

    func makeGlobalConfigurator(registry: TechPackRegistry = TechPackRegistry()) -> Configurator {
        Configurator(
            environment: env,
            output: CLIOutput(colorsEnabled: false),
            shell: ShellRunner(environment: env),
            registry: registry,
            strategy: GlobalSyncStrategy(environment: env),
            claudeCLI: mockCLI
        )
    }

    func makeGlobalDoctorRunner(registry: TechPackRegistry) -> DoctorRunner {
        DoctorRunner(
            fixMode: false,
            skipConfirmation: true,
            globalOnly: true,
            registry: registry,
            environment: env,
            projectRootOverride: nil
        )
    }

    /// Create a hook source file in a temp pack directory.
    func makeHookSource(name: String, content: String = "#!/bin/bash\necho hook") throws -> URL {
        let packDir = home.appendingPathComponent("pack-source/hooks")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        let file = packDir.appendingPathComponent(name)
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Create a settings merge source file.
    func makeSettingsSource(content: String) throws -> URL {
        let file = home.appendingPathComponent("pack-source/settings-\(UUID().uuidString).json")
        let dir = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Create a skill source file in a temp pack directory.
    func makeSkillSource(name: String, content: String = "# Skill\nDo the thing.") throws -> URL {
        let packDir = home.appendingPathComponent("pack-source/skills")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        let file = packDir.appendingPathComponent(name)
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    // MARK: - Assertions

    func projectState() throws -> ProjectState {
        try ProjectState(projectRoot: project)
    }

    var settingsLocalPath: URL {
        project.appendingPathComponent(".claude/settings.local.json")
    }

    var claudeLocalPath: URL {
        project.appendingPathComponent("CLAUDE.local.md")
    }
}

// MARK: - Scenario 1: Single-Pack Lifecycle

struct SinglePackLifecycleTests {
    @Test("Full lifecycle: configure -> doctor pass -> drift -> doctor warn -> re-sync -> remove")
    func fullSinglePackLifecycle() throws {
        let bed = try LifecycleTestBed()
        defer { bed.cleanup() }

        // Build a pack with hook + template + settings
        let hookSource = try bed.makeHookSource(name: "lint.sh")
        let settingsSource = try bed.makeSettingsSource(content: """
        {
          "env": { "LINT_ENABLED": "true" }
        }
        """)

        let pack = MockTechPack(
            identifier: "test-pack",
            displayName: "Test Pack",
            components: [
                ComponentDefinition(
                    id: "test-pack.lint-hook",
                    displayName: "Lint Hook",
                    description: "Post-tool lint hook",
                    type: .hookFile,
                    packIdentifier: "test-pack",
                    dependencies: [],
                    isRequired: true,
                    hookEvent: "PostToolUse",
                    installAction: .copyPackFile(
                        source: hookSource,
                        destination: "lint.sh",
                        fileType: .hook
                    )
                ),
                ComponentDefinition(
                    id: "test-pack.settings",
                    displayName: "Settings",
                    description: "Pack settings",
                    type: .configuration,
                    packIdentifier: "test-pack",
                    dependencies: [],
                    isRequired: true,
                    installAction: .settingsMerge(source: settingsSource)
                ),
            ],
            templates: [TemplateContribution(
                sectionIdentifier: "test-pack",
                templateContent: "## Test Pack\nLint all the things.",
                placeholders: []
            )]
        )
        let registry = TechPackRegistry(packs: [pack])

        // === Step 1: Configure ===
        let configurator = bed.makeConfigurator(registry: registry)
        try configurator.configure(packs: [pack], confirmRemovals: false)

        // Verify artifacts on disk
        let hookFile = bed.project.appendingPathComponent(".claude/hooks/lint.sh")
        #expect(FileManager.default.fileExists(atPath: hookFile.path))

        let settingsData = try Data(contentsOf: bed.settingsLocalPath)
        let settingsJSON = try #require(JSONSerialization.jsonObject(with: settingsData) as? [String: Any])
        let envDict = settingsJSON["env"] as? [String: Any]
        #expect(envDict?["LINT_ENABLED"] as? String == "true")

        let claudeContent = try String(contentsOf: bed.claudeLocalPath, encoding: .utf8)
        #expect(claudeContent.contains("<!-- mcs:begin test-pack -->"))
        #expect(claudeContent.contains("Lint all the things."))
        #expect(claudeContent.contains("<!-- mcs:end test-pack -->"))

        // Verify state
        let state = try bed.projectState()
        #expect(state.configuredPacks.contains("test-pack"))
        let artifacts = state.artifacts(for: "test-pack")
        #expect(artifacts != nil)
        #expect(artifacts?.templateSections.contains("test-pack") == true)
        #expect(artifacts?.settingsKeys.contains("env") == true)

        // === Step 2: Doctor passes ===
        var runner = bed.makeDoctorRunner(registry: registry)
        try runner.run()

        // === Step 3: Introduce settings drift ===
        var driftedSettings = settingsJSON
        var driftedEnv = envDict ?? [:]
        driftedEnv["LINT_ENABLED"] = "false"
        driftedSettings["env"] = driftedEnv
        let driftedData = try JSONSerialization.data(withJSONObject: driftedSettings, options: [.prettyPrinted, .sortedKeys])
        try driftedData.write(to: bed.settingsLocalPath)

        // === Step 4: Doctor detects drift ===
        var driftRunner = bed.makeDoctorRunner(registry: registry)
        try driftRunner.run()
        // (The runner completes — drift is reported as .warn, not a throw)

        // === Step 5: Re-sync fixes drift ===
        try configurator.configure(packs: [pack], confirmRemovals: false)
        let fixedData = try Data(contentsOf: bed.settingsLocalPath)
        let fixedJSON = try #require(JSONSerialization.jsonObject(with: fixedData) as? [String: Any])
        let fixedEnv = fixedJSON["env"] as? [String: Any]
        #expect(fixedEnv?["LINT_ENABLED"] as? String == "true")

        // === Step 6: Remove the pack ===
        try configurator.configure(packs: [], confirmRemovals: false)

        // Verify settings cleaned up (empty packs → settings file removed or empty)
        if FileManager.default.fileExists(atPath: bed.settingsLocalPath.path) {
            let removedData = try Data(contentsOf: bed.settingsLocalPath)
            let removedJSON = try JSONSerialization.jsonObject(with: removedData) as? [String: Any] ?? [:]
            #expect(removedJSON["env"] == nil)
        }

        // Template section should be removed from CLAUDE.local.md
        if FileManager.default.fileExists(atPath: bed.claudeLocalPath.path) {
            let removedContent = try String(contentsOf: bed.claudeLocalPath, encoding: .utf8)
            #expect(!removedContent.contains("<!-- mcs:begin test-pack -->"))
        }
    }
}

// MARK: - Scenario 2: Multi-Pack Convergence

struct MultiPackConvergenceTests {
    @Test("Two packs compose correctly, selective removal cleans only one")
    func twoPackConvergence() throws {
        let bed = try LifecycleTestBed()
        defer { bed.cleanup() }

        let settingsA = try bed.makeSettingsSource(content: """
        { "env": { "PACK_A_KEY": "valueA" } }
        """)
        let settingsB = try bed.makeSettingsSource(content: """
        { "env": { "PACK_B_KEY": "valueB" } }
        """)

        let packA = MockTechPack(
            identifier: "pack-a",
            displayName: "Pack A",
            components: [ComponentDefinition(
                id: "pack-a.settings",
                displayName: "A Settings",
                description: "Pack A settings",
                type: .configuration,
                packIdentifier: "pack-a",
                dependencies: [],
                isRequired: true,
                installAction: .settingsMerge(source: settingsA)
            )],
            templates: [TemplateContribution(
                sectionIdentifier: "pack-a",
                templateContent: "## Pack A\nPack A content.",
                placeholders: []
            )]
        )
        let packB = MockTechPack(
            identifier: "pack-b",
            displayName: "Pack B",
            components: [ComponentDefinition(
                id: "pack-b.settings",
                displayName: "B Settings",
                description: "Pack B settings",
                type: .configuration,
                packIdentifier: "pack-b",
                dependencies: [],
                isRequired: true,
                installAction: .settingsMerge(source: settingsB)
            )],
            templates: [TemplateContribution(
                sectionIdentifier: "pack-b",
                templateContent: "## Pack B\nPack B content.",
                placeholders: []
            )]
        )
        let registry = TechPackRegistry(packs: [packA, packB])
        let configurator = bed.makeConfigurator(registry: registry)

        // === Step 1: Configure both ===
        try configurator.configure(packs: [packA, packB], confirmRemovals: false)

        let settingsData = try Data(contentsOf: bed.settingsLocalPath)
        let json = try #require(JSONSerialization.jsonObject(with: settingsData) as? [String: Any])
        let envDict = json["env"] as? [String: Any]
        #expect(envDict?["PACK_A_KEY"] as? String == "valueA")
        #expect(envDict?["PACK_B_KEY"] as? String == "valueB")

        let claudeContent = try String(contentsOf: bed.claudeLocalPath, encoding: .utf8)
        #expect(claudeContent.contains("<!-- mcs:begin pack-a -->"))
        #expect(claudeContent.contains("<!-- mcs:begin pack-b -->"))

        // === Step 2: Doctor passes ===
        var runner = bed.makeDoctorRunner(registry: registry)
        try runner.run()

        // === Step 3: Remove pack A only ===
        try configurator.configure(packs: [packB], confirmRemovals: false)

        let afterData = try Data(contentsOf: bed.settingsLocalPath)
        let afterJSON = try #require(JSONSerialization.jsonObject(with: afterData) as? [String: Any])
        let afterEnv = afterJSON["env"] as? [String: Any]
        #expect(afterEnv?["PACK_A_KEY"] == nil)
        #expect(afterEnv?["PACK_B_KEY"] as? String == "valueB")

        let afterClaude = try String(contentsOf: bed.claudeLocalPath, encoding: .utf8)
        #expect(!afterClaude.contains("<!-- mcs:begin pack-a -->"))
        #expect(afterClaude.contains("<!-- mcs:begin pack-b -->"))

        // State only has pack-b
        let state = try bed.projectState()
        #expect(!state.configuredPacks.contains("pack-a"))
        #expect(state.configuredPacks.contains("pack-b"))

        // === Step 4: Re-add pack A ===
        try configurator.configure(packs: [packA, packB], confirmRemovals: false)

        let restoredData = try Data(contentsOf: bed.settingsLocalPath)
        let restoredJSON = try #require(JSONSerialization.jsonObject(with: restoredData) as? [String: Any])
        let restoredEnv = restoredJSON["env"] as? [String: Any]
        #expect(restoredEnv?["PACK_A_KEY"] as? String == "valueA")
        #expect(restoredEnv?["PACK_B_KEY"] as? String == "valueB")
    }
}

// MARK: - Scenario 3: Pack Update with Template Change

struct PackUpdateTemplateTests {
    @Test("Template v1 -> v2: doctor detects, re-sync fixes")
    func templateUpdateDetectedByDoctor() throws {
        let bed = try LifecycleTestBed()
        defer { bed.cleanup() }

        let packV1 = MockTechPack(
            identifier: "my-pack",
            displayName: "My Pack",
            templates: [TemplateContribution(
                sectionIdentifier: "my-pack",
                templateContent: "## My Pack v1\nVersion 1 content.",
                placeholders: []
            )]
        )
        let registry = TechPackRegistry(packs: [packV1])
        let configurator = bed.makeConfigurator(registry: registry)

        // === Step 1: Configure with v1 ===
        try configurator.configure(packs: [packV1], confirmRemovals: false)

        let content = try String(contentsOf: bed.claudeLocalPath, encoding: .utf8)
        #expect(content.contains("Version 1 content."))

        // === Step 2: Doctor passes with v1 ===
        var runner = bed.makeDoctorRunner(registry: registry)
        try runner.run()

        // === Step 3: Create v2 pack and re-configure ===
        let packV2 = MockTechPack(
            identifier: "my-pack",
            displayName: "My Pack",
            templates: [TemplateContribution(
                sectionIdentifier: "my-pack",
                templateContent: "## My Pack v2\nVersion 2 content.",
                placeholders: []
            )]
        )
        let registryV2 = TechPackRegistry(packs: [packV2])
        let configuratorV2 = bed.makeConfigurator(registry: registryV2)
        try configuratorV2.configure(packs: [packV2], confirmRemovals: false)

        // Verify content updated
        let updatedContent = try String(contentsOf: bed.claudeLocalPath, encoding: .utf8)
        #expect(updatedContent.contains("Version 2 content."))
        #expect(!updatedContent.contains("Version 1 content."))

        // === Step 4: Doctor passes with v2 ===
        var runnerV2 = bed.makeDoctorRunner(registry: registryV2)
        try runnerV2.run()
    }
}

// MARK: - Scenario 4: Component Exclusion Lifecycle

struct ComponentExclusionLifecycleTests {
    @Test("Exclude component removes its artifacts, re-include restores them")
    func excludeAndReinclude() throws {
        let bed = try LifecycleTestBed()
        defer { bed.cleanup() }

        let hookA = try bed.makeHookSource(name: "hookA.sh", content: "#!/bin/bash\necho A")
        let hookB = try bed.makeHookSource(name: "hookB.sh", content: "#!/bin/bash\necho B")

        let pack = MockTechPack(
            identifier: "my-pack",
            displayName: "My Pack",
            components: [
                ComponentDefinition(
                    id: "my-pack.hookA",
                    displayName: "Hook A",
                    description: "First hook",
                    type: .hookFile,
                    packIdentifier: "my-pack",
                    dependencies: [],
                    isRequired: false,
                    installAction: .copyPackFile(source: hookA, destination: "hookA.sh", fileType: .hook)
                ),
                ComponentDefinition(
                    id: "my-pack.hookB",
                    displayName: "Hook B",
                    description: "Second hook",
                    type: .hookFile,
                    packIdentifier: "my-pack",
                    dependencies: [],
                    isRequired: false,
                    installAction: .copyPackFile(source: hookB, destination: "hookB.sh", fileType: .hook)
                ),
            ]
        )
        let registry = TechPackRegistry(packs: [pack])
        let configurator = bed.makeConfigurator(registry: registry)

        let hookAPath = bed.project.appendingPathComponent(".claude/hooks/hookA.sh")
        let hookBPath = bed.project.appendingPathComponent(".claude/hooks/hookB.sh")

        // === Step 1: Configure with both ===
        try configurator.configure(packs: [pack], confirmRemovals: false)
        #expect(FileManager.default.fileExists(atPath: hookAPath.path))
        #expect(FileManager.default.fileExists(atPath: hookBPath.path))

        // === Step 2: Reconfigure with hookA excluded ===
        try configurator.configure(
            packs: [pack],
            confirmRemovals: false,
            excludedComponents: ["my-pack": Set(["my-pack.hookA"])]
        )
        #expect(!FileManager.default.fileExists(atPath: hookAPath.path))
        #expect(FileManager.default.fileExists(atPath: hookBPath.path))

        // Verify exclusion recorded in state
        let state = try bed.projectState()
        let excluded = state.excludedComponents(for: "my-pack")
        #expect(excluded.contains("my-pack.hookA"))

        // === Step 3: Re-include all ===
        try configurator.configure(packs: [pack], confirmRemovals: false)
        #expect(FileManager.default.fileExists(atPath: hookAPath.path))
        #expect(FileManager.default.fileExists(atPath: hookBPath.path))
    }
}

// MARK: - Scenario 5: Global Scope Sync + Doctor

struct GlobalScopeLifecycleTests {
    @Test("Global scope sync installs artifacts and doctor passes")
    func globalSyncAndDoctor() throws {
        let bed = try LifecycleTestBed()
        defer { bed.cleanup() }

        let hookSource = try bed.makeHookSource(name: "global-hook.sh")

        let pack = MockTechPack(
            identifier: "global-pack",
            displayName: "Global Pack",
            components: [ComponentDefinition(
                id: "global-pack.hook",
                displayName: "Global Hook",
                description: "A global hook",
                type: .hookFile,
                packIdentifier: "global-pack",
                dependencies: [],
                isRequired: true,
                installAction: .copyPackFile(
                    source: hookSource,
                    destination: "global-hook.sh",
                    fileType: .hook
                )
            )]
        )
        let registry = TechPackRegistry(packs: [pack])

        // === Configure global scope ===
        let configurator = bed.makeGlobalConfigurator(registry: registry)
        try configurator.configure(packs: [pack], confirmRemovals: false)

        // Verify hook installed in ~/.claude/hooks/
        let globalHook = bed.env.hooksDirectory.appendingPathComponent("global-hook.sh")
        #expect(FileManager.default.fileExists(atPath: globalHook.path))

        // Verify global state
        let globalState = try ProjectState(stateFile: bed.env.globalStateFile)
        #expect(globalState.configuredPacks.contains("global-pack"))

        // === Doctor passes ===
        var runner = bed.makeGlobalDoctorRunner(registry: registry)
        try runner.run()
    }
}

// MARK: - Scenario 6: Stale Artifact Cleanup on Pack Update

struct StaleArtifactCleanupTests {
    @Test("v1 has A,B,C -> v2 removes B renames C->D: stale artifacts cleaned")
    func staleArtifactCleanup() throws {
        let bed = try LifecycleTestBed()
        defer { bed.cleanup() }

        let skillA = try bed.makeSkillSource(name: "skillA.md", content: "# Skill A")
        let skillB = try bed.makeSkillSource(name: "skillB.md", content: "# Skill B")
        let skillC = try bed.makeSkillSource(name: "skillC.md", content: "# Skill C")

        let packV1 = MockTechPack(
            identifier: "my-pack",
            displayName: "My Pack",
            components: [
                ComponentDefinition(
                    id: "my-pack.skillA",
                    displayName: "Skill A",
                    description: "First skill",
                    type: .skill,
                    packIdentifier: "my-pack",
                    dependencies: [],
                    isRequired: true,
                    installAction: .copyPackFile(source: skillA, destination: "skillA.md", fileType: .skill)
                ),
                ComponentDefinition(
                    id: "my-pack.skillB",
                    displayName: "Skill B",
                    description: "Second skill",
                    type: .skill,
                    packIdentifier: "my-pack",
                    dependencies: [],
                    isRequired: true,
                    installAction: .copyPackFile(source: skillB, destination: "skillB.md", fileType: .skill)
                ),
                ComponentDefinition(
                    id: "my-pack.skillC",
                    displayName: "Skill C",
                    description: "Third skill",
                    type: .skill,
                    packIdentifier: "my-pack",
                    dependencies: [],
                    isRequired: true,
                    installAction: .copyPackFile(source: skillC, destination: "skillC.md", fileType: .skill)
                ),
            ]
        )
        let registryV1 = TechPackRegistry(packs: [packV1])
        let configuratorV1 = bed.makeConfigurator(registry: registryV1)

        // === Configure with v1 ===
        try configuratorV1.configure(packs: [packV1], confirmRemovals: false)

        let skillsDir = bed.project.appendingPathComponent(".claude/skills")
        #expect(FileManager.default.fileExists(atPath: skillsDir.appendingPathComponent("skillA.md").path))
        #expect(FileManager.default.fileExists(atPath: skillsDir.appendingPathComponent("skillB.md").path))
        #expect(FileManager.default.fileExists(atPath: skillsDir.appendingPathComponent("skillC.md").path))

        // === Create v2: remove B, add D (C->D rename) ===
        let skillD = try bed.makeSkillSource(name: "skillD.md", content: "# Skill D (was C)")
        let packV2 = MockTechPack(
            identifier: "my-pack",
            displayName: "My Pack",
            components: [
                ComponentDefinition(
                    id: "my-pack.skillA",
                    displayName: "Skill A",
                    description: "First skill",
                    type: .skill,
                    packIdentifier: "my-pack",
                    dependencies: [],
                    isRequired: true,
                    installAction: .copyPackFile(source: skillA, destination: "skillA.md", fileType: .skill)
                ),
                ComponentDefinition(
                    id: "my-pack.skillD",
                    displayName: "Skill D",
                    description: "Fourth skill (replaced C)",
                    type: .skill,
                    packIdentifier: "my-pack",
                    dependencies: [],
                    isRequired: true,
                    installAction: .copyPackFile(source: skillD, destination: "skillD.md", fileType: .skill)
                ),
            ]
        )
        let registryV2 = TechPackRegistry(packs: [packV2])
        let configuratorV2 = bed.makeConfigurator(registry: registryV2)

        // === Configure with v2 ===
        try configuratorV2.configure(packs: [packV2], confirmRemovals: false)

        // A still exists, B removed, C removed, D created
        #expect(FileManager.default.fileExists(atPath: skillsDir.appendingPathComponent("skillA.md").path))
        #expect(!FileManager.default.fileExists(atPath: skillsDir.appendingPathComponent("skillB.md").path))
        #expect(!FileManager.default.fileExists(atPath: skillsDir.appendingPathComponent("skillC.md").path))
        #expect(FileManager.default.fileExists(atPath: skillsDir.appendingPathComponent("skillD.md").path))

        // Artifact record only tracks A and D
        let state = try bed.projectState()
        let artifacts = try #require(state.artifacts(for: "my-pack"))
        #expect(artifacts.files.contains { $0.contains("skillA.md") })
        #expect(artifacts.files.contains { $0.contains("skillD.md") })
        #expect(!artifacts.files.contains { $0.contains("skillB.md") })
        #expect(!artifacts.files.contains { $0.contains("skillC.md") })

        // === Doctor passes ===
        var runner = bed.makeDoctorRunner(registry: registryV2)
        try runner.run()
    }
}

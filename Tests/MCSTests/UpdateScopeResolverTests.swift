import Foundation
@testable import mcs
import Testing

struct UpdateScopeResolverTests {
    private func setup(
        globalPacks: [String] = [],
        projectPacks: [String]? = nil
    ) throws -> (home: URL, project: URL, env: Environment) {
        let home = try makeGlobalTmpDir(label: "update-resolver")
        let project = home.appendingPathComponent("test-project")
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent(Constants.FileNames.claudeDirectory),
            withIntermediateDirectories: true
        )

        let env = Environment(home: home)

        var indexData = ProjectIndex.IndexData()
        let indexFile = ProjectIndex(path: env.projectsIndexFile)

        if !globalPacks.isEmpty {
            indexFile.upsert(
                projectPath: ProjectIndex.globalSentinel,
                packIDs: globalPacks,
                in: &indexData
            )
            var globalState = try ProjectState(stateFile: env.globalStateFile)
            for pack in globalPacks {
                globalState.recordPack(pack)
            }
            try globalState.save()
        }

        if let projectPacks {
            indexFile.upsert(
                projectPath: project.standardizedFileURL.path,
                packIDs: projectPacks,
                in: &indexData
            )
            var projectState = try ProjectState(projectRoot: project)
            for pack in projectPacks {
                projectState.recordPack(pack)
            }
            try projectState.save()
        }

        try indexFile.save(indexData)
        return (home, project, env)
    }

    @Test("Empty index returns no scopes")
    func emptyIndex() throws {
        let home = try makeGlobalTmpDir(label: "update-resolver-empty")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        let resolver = UpdateScopeResolver(environment: env, output: CLIOutput(colorsEnabled: false))
        let runs = try resolver.resolve(filter: .currentScopes, projectRoot: nil)
        #expect(runs.isEmpty)
    }

    @Test("Global-only configured returns one global run")
    func globalOnly() throws {
        let (home, _, env) = try setup(globalPacks: ["pack-a"])
        defer { try? FileManager.default.removeItem(at: home) }

        let resolver = UpdateScopeResolver(environment: env, output: CLIOutput(colorsEnabled: false))
        let runs = try resolver.resolve(filter: .currentScopes, projectRoot: nil)
        #expect(runs.count == 1)
        #expect(runs[0].isGlobal)
        #expect(runs[0].configuredPackIDs == ["pack-a"])
    }

    @Test("Both scopes return two runs in global → project order")
    func bothScopes() throws {
        let (home, project, env) = try setup(
            globalPacks: ["pack-a"],
            projectPacks: ["pack-b"]
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let resolver = UpdateScopeResolver(environment: env, output: CLIOutput(colorsEnabled: false))
        let runs = try resolver.resolve(filter: .currentScopes, projectRoot: project)
        #expect(runs.count == 2)
        #expect(runs[0].isGlobal)
        #expect(runs[0].configuredPackIDs == ["pack-a"])
        #expect(!runs[1].isGlobal)
        #expect(runs[1].configuredPackIDs == ["pack-b"])
        #expect(runs[1].projectPath?.standardizedFileURL == project.standardizedFileURL)
    }

    @Test("Filter .globalOnly excludes the project scope")
    func filterGlobalOnly() throws {
        let (home, project, env) = try setup(
            globalPacks: ["pack-a"],
            projectPacks: ["pack-b"]
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let resolver = UpdateScopeResolver(environment: env, output: CLIOutput(colorsEnabled: false))
        let runs = try resolver.resolve(filter: .globalOnly, projectRoot: project)
        #expect(runs.count == 1)
        #expect(runs[0].isGlobal)
    }

    @Test("Filter .projectOnly excludes the global scope")
    func filterProjectOnly() throws {
        let (home, project, env) = try setup(
            globalPacks: ["pack-a"],
            projectPacks: ["pack-b"]
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let resolver = UpdateScopeResolver(environment: env, output: CLIOutput(colorsEnabled: false))
        let runs = try resolver.resolve(filter: .projectOnly, projectRoot: project)
        #expect(runs.count == 1)
        #expect(!runs[0].isGlobal)
        #expect(runs[0].configuredPackIDs == ["pack-b"])
    }

    @Test("Project not in index returns no project run")
    func projectNotInIndex() throws {
        let (home, project, env) = try setup(globalPacks: ["pack-a"])
        defer { try? FileManager.default.removeItem(at: home) }

        let resolver = UpdateScopeResolver(environment: env, output: CLIOutput(colorsEnabled: false))
        let runs = try resolver.resolve(filter: .currentScopes, projectRoot: project)
        #expect(runs.count == 1)
        #expect(runs[0].isGlobal)
    }

    @Test("Filter .everywhere returns global plus every project in the index")
    func everywhereFansOut() throws {
        let home = try makeGlobalTmpDir(label: "update-resolver-everywhere")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        var indexData = ProjectIndex.IndexData()
        let indexFile = ProjectIndex(path: env.projectsIndexFile)
        indexFile.upsert(projectPath: ProjectIndex.globalSentinel, packIDs: ["pack-a"], in: &indexData)

        let projectA = home.appendingPathComponent("proj-a")
        let projectB = home.appendingPathComponent("proj-b")
        for project in [projectA, projectB] {
            try FileManager.default.createDirectory(
                at: project.appendingPathComponent(Constants.FileNames.claudeDirectory),
                withIntermediateDirectories: true
            )
            indexFile.upsert(
                projectPath: project.standardizedFileURL.path,
                packIDs: ["pack-b"],
                in: &indexData
            )
            var state = try ProjectState(projectRoot: project)
            state.recordPack("pack-b")
            try state.save()
        }
        var globalState = try ProjectState(stateFile: env.globalStateFile)
        globalState.recordPack("pack-a")
        try globalState.save()
        try indexFile.save(indexData)

        let resolver = UpdateScopeResolver(environment: env, output: CLIOutput(colorsEnabled: false))
        let runs = try resolver.resolve(filter: .everywhere, projectRoot: nil)
        #expect(runs.count == 3)
        #expect(runs[0].isGlobal)
        let projectRunPaths = Set(runs.dropFirst().compactMap { $0.projectPath?.standardizedFileURL.path })
        #expect(projectRunPaths == [projectA.standardizedFileURL.path, projectB.standardizedFileURL.path])
    }

    @Test("Stale project entries are pruned from the index under .everywhere")
    func staleEntriesPruned() throws {
        let home = try makeGlobalTmpDir(label: "update-resolver-stale")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        var indexData = ProjectIndex.IndexData()
        let indexFile = ProjectIndex(path: env.projectsIndexFile)
        indexFile.upsert(
            projectPath: "/nonexistent/path/to/project",
            packIDs: ["pack-x"],
            in: &indexData
        )
        try indexFile.save(indexData)

        let resolver = UpdateScopeResolver(environment: env, output: CLIOutput(colorsEnabled: false))
        let runs = try resolver.resolve(filter: .everywhere, projectRoot: nil)
        #expect(runs.isEmpty)

        let reloaded = try indexFile.load()
        #expect(reloaded.projects.isEmpty)
    }

    @Test("Dry-run .everywhere does not rewrite the pruned index to disk")
    func dryRunDoesNotPruneOnDisk() throws {
        let home = try makeGlobalTmpDir(label: "update-resolver-stale-dry")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        let stalePath = "/nonexistent/path/to/project"
        var indexData = ProjectIndex.IndexData()
        let indexFile = ProjectIndex(path: env.projectsIndexFile)
        indexFile.upsert(projectPath: stalePath, packIDs: ["pack-x"], in: &indexData)
        try indexFile.save(indexData)

        let resolver = UpdateScopeResolver(environment: env, output: CLIOutput(colorsEnabled: false))
        let runs = try resolver.resolve(filter: .everywhere, projectRoot: nil, dryRun: true)
        #expect(runs.isEmpty)

        let reloaded = try indexFile.load()
        #expect(reloaded.projects.count == 1)
        #expect(reloaded.projects.first?.path == stalePath)
    }

    @Test("Non-everywhere filters do not prune the index")
    func currentScopesDoesNotPrune() throws {
        let home = try makeGlobalTmpDir(label: "update-resolver-no-prune")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        let stalePath = "/nonexistent/path/to/project"
        var indexData = ProjectIndex.IndexData()
        let indexFile = ProjectIndex(path: env.projectsIndexFile)
        indexFile.upsert(projectPath: stalePath, packIDs: ["pack-x"], in: &indexData)
        try indexFile.save(indexData)

        let resolver = UpdateScopeResolver(environment: env, output: CLIOutput(colorsEnabled: false))
        _ = try resolver.resolve(filter: .currentScopes, projectRoot: nil)

        let reloaded = try indexFile.load()
        #expect(reloaded.projects.count == 1)
        #expect(reloaded.projects.first?.path == stalePath)
    }

    @Test("ProjectState is the source of truth — index entry is not required")
    func stateOverridesMissingIndexEntry() throws {
        let home = try makeGlobalTmpDir(label: "update-resolver-no-index")
        defer { try? FileManager.default.removeItem(at: home) }
        let env = Environment(home: home)

        var globalState = try ProjectState(stateFile: env.globalStateFile)
        globalState.recordPack("pack-a")
        try globalState.save()

        let resolver = UpdateScopeResolver(environment: env, output: CLIOutput(colorsEnabled: false))
        let runs = try resolver.resolve(filter: .currentScopes, projectRoot: nil)
        #expect(runs.count == 1)
        #expect(runs[0].isGlobal)
        #expect(runs[0].configuredPackIDs == ["pack-a"])
    }
}

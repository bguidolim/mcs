import Foundation

/// Resolves which scopes `mcs update` should refresh.
///
/// `ProjectState` is the source of truth for whether a scope has configured packs.
/// `~/.mcs/projects.yaml` is consulted only for project discovery (`.everywhere`)
/// and for stale-entry pruning, since the index write in sync is best-effort and
/// can lag behind state on a partial failure.
struct UpdateScopeResolver {
    let environment: Environment
    let output: CLIOutput

    enum Scope {
        case global
        case project(URL)

        var isGlobal: Bool {
            if case .global = self { true } else { false }
        }
    }

    struct ScopeRun {
        let scope: Scope
        let strategy: any SyncStrategy
        let configuredPackIDs: Set<String>
        let excludedComponents: [String: Set<String>]

        var isGlobal: Bool {
            scope.isGlobal
        }

        var label: String {
            switch scope {
            case .global: "Global"
            case let .project(url): "Project: \(url.path)"
            }
        }
    }

    enum Filter {
        case currentScopes
        case globalOnly
        case projectOnly
        case everywhere
    }

    func resolve(filter: Filter, projectRoot: URL?, dryRun: Bool = false) throws -> [ScopeRun] {
        var runs: [ScopeRun] = []

        if filter == .everywhere {
            try pruneStaleIndexEntries(dryRun: dryRun)
        }

        if filter != .projectOnly,
           let run = try buildRun(
               scope: .global,
               strategy: GlobalSyncStrategy(environment: environment)
           ) {
            runs.append(run)
        }

        switch filter {
        case .everywhere:
            let indexFile = ProjectIndex(path: environment.projectsIndexFile)
            let indexData = try indexFile.load()
            for entry in indexData.projects {
                guard let projectURL = entry.url?.standardizedFileURL else { continue }
                if let run = try buildRun(
                    scope: .project(projectURL),
                    strategy: ProjectSyncStrategy(projectPath: projectURL, environment: environment)
                ) {
                    runs.append(run)
                }
            }
        case .currentScopes, .projectOnly:
            if let projectRoot,
               let run = try buildRun(
                   scope: .project(projectRoot),
                   strategy: ProjectSyncStrategy(projectPath: projectRoot, environment: environment)
               ) {
                runs.append(run)
            }
        case .globalOnly:
            break
        }

        return runs
    }

    private func buildRun(scope: Scope, strategy: any SyncStrategy) throws -> ScopeRun? {
        let state = try ProjectState(stateFile: strategy.scope.stateFile)
        let configured = state.configuredPacks
        guard !configured.isEmpty else { return nil }

        return ScopeRun(
            scope: scope,
            strategy: strategy,
            configuredPackIDs: configured,
            excludedComponents: state.allExcludedComponents
        )
    }

    private func pruneStaleIndexEntries(dryRun: Bool) throws {
        let indexFile = ProjectIndex(path: environment.projectsIndexFile)
        var indexData = try indexFile.load()

        let pruned = indexFile.pruneStale(in: &indexData)
        guard !pruned.isEmpty else { return }

        if dryRun {
            output.dimmed("Would prune \(pruned.count) stale project entries from index (dry-run; pruned in memory only).")
        } else {
            output.dimmed("Pruned \(pruned.count) stale project entries from index.")
            try indexFile.save(indexData)
        }
    }
}

import ArgumentParser
import Foundation

/// Refresh-only orchestration. Lockfile writes honour the `generate-lockfile`
/// config — there is no force-write path.
struct UpdateCommand: LockedCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Fetch latest pack versions and re-apply across configured scopes"
    )

    @Argument(help: "Path to the project directory (defaults to current directory)")
    var path: String?

    @Flag(name: .long, help: "Only refresh the global scope")
    var global: Bool = false

    @Flag(name: .long, help: "Only refresh the current project's scope")
    var project: Bool = false

    @Flag(name: .customLong("all-projects"), help: "Refresh every project in the index plus the global scope (fan out machine-wide)")
    var allProjects: Bool = false

    @Flag(name: .long, help: "Show what would change without making any modifications")
    var dryRun = false

    var skipLock: Bool {
        dryRun
    }

    func perform() throws {
        let env = Environment()
        let output = CLIOutput()
        MCSAnalytics.initialize(env: env, output: output)
        defer { MCSAnalytics.trackCommand(.update) }
        let shell = ShellRunner(environment: env)

        guard ensureClaudeCLI(shell: shell, environment: env, output: output) else {
            throw ExitCode.failure
        }

        let (filter, projectRoot) = try resolveScopeSelection(output: output)

        let resolver = UpdateScopeResolver(environment: env, output: output)
        let runs = try resolver.resolve(filter: filter, projectRoot: projectRoot, dryRun: dryRun)

        guard !runs.isEmpty else {
            output.info("Nothing to update — no scopes have configured packs.")
            return
        }

        if allProjects, !confirmFanOut(runs: runs, env: env, output: output) {
            output.info("Update cancelled.")
            return
        }

        warnIfProjectScopeMissing(filter: filter, projectRoot: projectRoot, runs: runs, output: output)

        let configuredAcrossScopes = Set(runs.flatMap(\.configuredPackIDs))

        let registryFile = PackRegistryFile(path: env.packsRegistry)
        let registryData = try registryFile.load()

        let (updatedRegistryData, updates, skippedPackIDs) = runUpdatePhase(
            packIDsToUpdate: configuredAcrossScopes,
            registryFile: registryFile,
            registryData: registryData,
            env: env,
            shell: shell,
            output: output
        )

        try persistRegistryUpdates(
            registryFile: registryFile,
            updatedData: updatedRegistryData,
            updates: updates,
            output: output
        )

        let techPackRegistry = TechPackRegistry.loadWithExternalPacks(
            environment: env,
            output: output
        )

        let reapplyFailures = runReapplyPhase(
            runs: runs,
            skippedPackIDs: skippedPackIDs,
            registry: techPackRegistry,
            env: env,
            shell: shell,
            output: output
        )

        let lockfileFailures = runLockfilePhase(runs: runs, env: env, shell: shell, output: output)

        if !dryRun {
            // mcs update has just authoritatively re-checked every configured pack's
            // upstream state; any cached "X has updates" notification is now stale.
            if !UpdateChecker.invalidateCache(environment: env) {
                output.warn("Could not clear update check cache at \(env.updateCheckCacheFile.path).")
            }
            UpdateChecker.checkAndPrint(env: env, shell: shell, output: output)
        }

        if !reapplyFailures.isEmpty || !lockfileFailures.isEmpty {
            throw ExitCode.failure
        }
    }

    // MARK: - Helpers

    private enum ScopeFlag: String {
        case global = "--global"
        case project = "--project"
        case allProjects = "--all-projects"
    }

    private var activeScopeFlags: [ScopeFlag] {
        var flags: [ScopeFlag] = []
        if global { flags.append(.global) }
        if project { flags.append(.project) }
        if allProjects { flags.append(.allProjects) }
        return flags
    }

    private func resolveScopeSelection(
        output: CLIOutput
    ) throws -> (UpdateScopeResolver.Filter, URL?) {
        let active = activeScopeFlags
        guard active.count <= 1 else {
            let names = active.map(\.rawValue).joined(separator: ", ")
            output.error("\(names) are mutually exclusive.")
            throw ExitCode.failure
        }

        if path != nil, let scope = active.first, scope != .project {
            output.warn("Positional path argument is ignored under \(scope.rawValue).")
        }

        switch active.first {
        case .allProjects:
            return (.everywhere, nil)
        case .global:
            return (.globalOnly, nil)
        case .project:
            guard let root = detectProjectRoot() else {
                output.error("--project specified but no project root detected at \(targetPath.path).")
                output.plain("  cd into a project directory, pass a path, or omit --project.")
                throw ExitCode.failure
            }
            return (.projectOnly, root)
        case .none:
            return (.currentScopes, detectProjectRoot())
        }
    }

    private func confirmFanOut(
        runs: [UpdateScopeResolver.ScopeRun],
        env: Environment,
        output: CLIOutput
    ) -> Bool {
        guard !dryRun, output.hasInteractiveStdin else { return true }

        let projectPaths: [URL] = runs.compactMap { run in
            if case let .project(path) = run.scope { path } else { nil }
        }
        let hasGlobal = runs.contains(where: \.isGlobal)
        guard !projectPaths.isEmpty || hasGlobal else { return true }

        let scopeSummary = if hasGlobal, !projectPaths.isEmpty {
            "the global scope plus \(projectPaths.count) project(s)"
        } else if hasGlobal {
            "the global scope"
        } else {
            "\(projectPaths.count) project(s)"
        }

        output.warn("--all-projects will refresh \(scopeSummary):")
        if hasGlobal {
            output.plain("  • global (\(env.claudeDirectory.path))")
        }
        for path in projectPaths {
            output.plain("  • \(path.path)")
        }
        output.plain("  Each project's pack-defined hooks will run with that project as cwd.")
        output.plain("  Uncommitted changes in those projects may be overwritten by managed files.")
        output.plain("")
        return output.askYesNo("Proceed?", default: false)
    }

    private func warnIfProjectScopeMissing(
        filter: UpdateScopeResolver.Filter,
        projectRoot: URL?,
        runs: [UpdateScopeResolver.ScopeRun],
        output: CLIOutput
    ) {
        guard filter == .currentScopes else { return }
        guard !runs.contains(where: { !$0.isGlobal }) else { return }

        if let projectRoot {
            output.warn("Project at \(projectRoot.path) has no configured packs — only refreshing the global scope.")
            output.plain("  Run 'mcs sync' inside the project to configure packs there first.")
        } else {
            output.warn("Not in a project directory — only refreshing the global scope.")
            output.plain("  cd into a project to also refresh its packs.")
        }
    }

    private var targetPath: URL {
        if let path {
            URL(fileURLWithPath: path)
        } else {
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
    }

    private func detectProjectRoot() -> URL? {
        ProjectDetector.findProjectRoot(from: targetPath)
    }

    /// Buffered so success messages don't print before the registry save persists.
    private struct UpdateRecord {
        let displayName: String
        let priorSHA: String
        let newSHA: String
    }

    private func runUpdatePhase(
        packIDsToUpdate: Set<String>,
        registryFile: PackRegistryFile,
        registryData: PackRegistryFile.RegistryData,
        env: Environment,
        shell: ShellRunner,
        output: CLIOutput
    ) -> (data: PackRegistryFile.RegistryData, updates: [UpdateRecord], skipped: Set<String>) {
        var updatedData = registryData
        var updates: [UpdateRecord] = []
        var skipped: Set<String> = []

        let entries = registryData.packs.filter { packIDsToUpdate.contains($0.identifier) }
        guard !entries.isEmpty else { return (updatedData, updates, skipped) }

        output.header("Updating packs")

        if dryRun {
            for entry in entries {
                output.dimmed("  \(entry.displayName): would check for updates")
            }
            return (updatedData, updates, skipped)
        }

        let updater = PackUpdater(
            fetcher: PackFetcher(shell: shell, output: output, packsDirectory: env.packsDirectory),
            trustManager: PackTrustManager(output: output),
            environment: env,
            output: output
        )

        for entry in entries {
            if entry.isLocalPack {
                output.dimmed("  \(entry.displayName): local pack (skipped)")
                continue
            }

            guard let packPath = entry.resolvedPath(packsDirectory: env.packsDirectory) else {
                output.warn("  \(entry.identifier): invalid path — skipping")
                skipped.insert(entry.identifier)
                continue
            }

            let result = updater.updateGitPack(entry: entry, packPath: packPath, registry: registryFile)
            switch result {
            case .alreadyUpToDate:
                output.dimmed("  \(entry.displayName): already up to date")
            case let .updated(updatedEntry):
                registryFile.register(updatedEntry, in: &updatedData)
                updates.append(UpdateRecord(
                    displayName: entry.displayName,
                    priorSHA: entry.shortSHA,
                    newSHA: updatedEntry.shortSHA
                ))
            case let .skipped(reason):
                output.warn("  \(entry.identifier): \(reason) (will re-prompt on next 'mcs update')")
                skipped.insert(entry.identifier)
            }
        }

        return (updatedData, updates, skipped)
    }

    private func persistRegistryUpdates(
        registryFile: PackRegistryFile,
        updatedData: PackRegistryFile.RegistryData,
        updates: [UpdateRecord],
        output: CLIOutput
    ) throws {
        guard !dryRun, !updates.isEmpty else { return }

        do {
            try registryFile.save(updatedData)
        } catch {
            output.error("Registry save failed — pack updates listed below were NOT persisted:")
            for update in updates {
                output.plain("  • \(update.displayName) (\(update.priorSHA) → \(update.newSHA))")
            }
            output.error(error.localizedDescription)
            throw ExitCode.failure
        }

        for update in updates {
            output.success("  \(update.displayName): \(update.priorSHA) → \(update.newSHA)")
        }
    }

    private func runReapplyPhase(
        runs: [UpdateScopeResolver.ScopeRun],
        skippedPackIDs: Set<String>,
        registry: TechPackRegistry,
        env: Environment,
        shell: ShellRunner,
        output: CLIOutput
    ) -> [String] {
        var failures: [String] = []

        for run in runs {
            output.header(run.label)

            let packIDs = run.configuredPackIDs.subtracting(skippedPackIDs).sorted()

            var packs: [any TechPack] = []
            var unresolved: [String] = []
            for packID in packIDs {
                if let pack = registry.pack(for: packID) {
                    packs.append(pack)
                } else {
                    unresolved.append(packID)
                }
            }

            for packID in unresolved {
                output.warn("  \(packID): tracked in state but missing from pack registry — skipping. Run 'mcs pack add' to restore it.")
            }

            guard !packs.isEmpty else {
                output.info("No packs to refresh in this scope.")
                continue
            }

            let configurator = Configurator(
                environment: env,
                output: output,
                shell: shell,
                registry: registry,
                strategy: run.strategy
            )

            do {
                if dryRun {
                    try configurator.dryRun(packs: packs)
                } else {
                    try configurator.configure(
                        packs: packs,
                        confirmRemovals: false,
                        excludedComponents: run.excludedComponents,
                        reusePriorValuesSilently: true
                    )
                }
            } catch {
                output.error("  \(run.label) failed: \(error.localizedDescription)")
                failures.append(run.label)
            }
        }

        return failures
    }

    /// `reportDrift` is purely diagnostic — a single project's failure must never
    /// suppress sibling drift warnings.
    private func runLockfilePhase(
        runs: [UpdateScopeResolver.ScopeRun],
        env: Environment,
        shell: ShellRunner,
        output: CLIOutput
    ) -> [String] {
        guard !dryRun else { return [] }

        let config = MCSConfig.load(from: env.mcsConfigFile, output: output)
        let lockOps = LockfileOperations(environment: env, output: output, shell: shell)
        var failures: [String] = []

        for run in runs {
            guard case let .project(projectPath) = run.scope else { continue }

            do {
                if config.isLockfileGenerationEnabled {
                    try lockOps.writeLockfile(at: projectPath)
                } else if config.isLockfileGenerationUnset {
                    try lockOps.reportDrift(at: projectPath)
                }
            } catch {
                output.warn("Lockfile (\(projectPath.path)): \(error.localizedDescription)")
                failures.append(projectPath.path)
            }
        }

        return failures
    }
}

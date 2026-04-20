import Foundation

/// Checks for available updates to tech packs (via `git ls-remote`)
/// and the mcs CLI itself (via `git ls-remote --tags` on the mcs repo).
///
/// All network operations fail silently — offline or unreachable
/// remotes produce no output, matching the design goal of non-intrusive checks.
struct UpdateChecker {
    let environment: Environment
    let shell: ShellRunner

    /// Default cooldown interval: 24 hours.
    static let cooldownInterval: TimeInterval = 86400

    /// Environment variables to suppress credential prompts during read-only git checks.
    /// GIT_TERMINAL_PROMPT=0 prevents terminal-based prompts; GIT_ASKPASS="" disables GUI credential helpers.
    private static let gitNoPromptEnv: [String: String] = [
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_ASKPASS": "",
    ]

    // MARK: - SessionStart Hook (single source of truth)

    static let hookCommand = "mcs check-updates --hook"
    static let hookTimeout: Int = 30
    static let hookStatusMessage = "Checking for updates..."

    @discardableResult
    static func addHook(to settings: inout Settings) -> Bool {
        settings.addHookEntry(
            event: Constants.HookEvent.sessionStart,
            command: hookCommand,
            timeout: hookTimeout,
            statusMessage: hookStatusMessage
        )
    }

    @discardableResult
    static func removeHook(from settings: inout Settings) -> Bool {
        settings.removeHookEntry(event: Constants.HookEvent.sessionStart, command: hookCommand)
    }

    /// Ensure the SessionStart hook in `~/.claude/settings.json` matches the config.
    static func syncHook(config: MCSConfig, env: Environment, output: CLIOutput) {
        do {
            var settings = try Settings.load(from: env.claudeSettings)
            if config.isUpdateCheckEnabled {
                if addHook(to: &settings) {
                    try settings.save(to: env.claudeSettings)
                }
            } else {
                if removeHook(from: &settings) {
                    try settings.save(to: env.claudeSettings)
                }
            }
        } catch {
            output.warn("Could not update hook in settings: \(error.localizedDescription)")
        }
    }

    /// Run an update check and print results. Used by sync and doctor.
    /// Respects the 24-hour cache cooldown — only does network checks when cache is stale.
    static func checkAndPrint(env: Environment, shell: ShellRunner, output: CLIOutput) {
        let packRegistry = PackRegistryFile(path: env.packsRegistry)
        let allEntries: [PackRegistryFile.PackEntry]
        do {
            allEntries = try packRegistry.load().packs
        } catch {
            output.warn("Could not load pack registry: \(error.localizedDescription)")
            allEntries = []
        }
        let relevantEntries = filterEntries(allEntries, environment: env)
        let checker = UpdateChecker(environment: env, shell: shell)
        let result = checker.performCheck(
            entries: relevantEntries,
            checkPacks: true,
            checkCLI: true
        )
        if !result.isEmpty {
            output.plain("")
            printResult(result, output: output)
        }
    }

    // MARK: - Result Types

    struct PackUpdate: Codable {
        let identifier: String
        let displayName: String
        let localSHA: String
        let remoteSHA: String
    }

    struct CLIUpdate: Codable {
        let currentVersion: String
        let latestVersion: String
    }

    struct CheckResult: Codable {
        let packUpdates: [PackUpdate]
        let cliUpdate: CLIUpdate?

        var isEmpty: Bool {
            packUpdates.isEmpty && cliUpdate == nil
        }

        private enum CodingKeys: String, CodingKey {
            case packUpdates = "packs"
            case cliUpdate = "cli"
        }
    }

    /// On-disk cache: check results + timestamp in a single JSON file.
    struct CachedResult: Codable {
        let timestamp: String
        let result: CheckResult
    }

    // MARK: - Cache

    /// Load the cached check result. Returns nil if missing, corrupt, or CLI version changed.
    func loadCache() -> CachedResult? {
        guard let data = try? Data(contentsOf: environment.updateCheckCacheFile),
              let cached = try? JSONDecoder().decode(CachedResult.self, from: data)
        else {
            return nil
        }
        // Invalidate if the CLI version changed (user upgraded mcs)
        if let cli = cached.result.cliUpdate,
           cli.currentVersion != MCSVersion.current {
            return nil
        }
        return cached
    }

    /// Save check results to the cache file.
    func saveCache(_ result: CheckResult) {
        let cached = CachedResult(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            result: result
        )
        do {
            let dir = environment.updateCheckCacheFile.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(cached)
            try data.write(to: environment.updateCheckCacheFile, options: .atomic)
        } catch {
            // Cache write failure is non-fatal — next check will just redo network calls
        }
    }

    /// Delete the cache file (e.g., after `mcs pack update`).
    /// Returns true if deleted or already absent; false on permission error.
    /// Callers must decide how to react to `false` — silently discarding it re-introduces
    /// the "stale update banner" defect from issue #334.
    static func invalidateCache(environment: Environment) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: environment.updateCheckCacheFile.path) else { return true }
        do {
            try fm.removeItem(at: environment.updateCheckCacheFile)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Pack Checks

    /// Check each git pack for remote updates via `git ls-remote`.
    /// Local packs are skipped. Checks run in parallel. Network failures are silently ignored per-pack.
    func checkPackUpdates(entries: [PackRegistryFile.PackEntry]) -> [PackUpdate] {
        let gitEntries = entries.filter { !$0.isLocalPack }
        guard !gitEntries.isEmpty else { return [] }

        // Each index is written by exactly one iteration — no data race.
        // nonisolated(unsafe) is needed because concurrentPerform's closure is @Sendable.
        nonisolated(unsafe) var results = [PackUpdate?](repeating: nil, count: gitEntries.count)

        DispatchQueue.concurrentPerform(iterations: gitEntries.count) { index in
            let entry = gitEntries[index]
            let ref = entry.ref ?? "HEAD"
            let result = shell.run(
                environment.gitPath,
                arguments: ["ls-remote", entry.sourceURL, ref],
                additionalEnvironment: Self.gitNoPromptEnv
            )

            guard result.succeeded,
                  let remoteSHA = Self.parseRemoteSHA(from: result.stdout)
            else {
                return
            }

            if remoteSHA != entry.commitSHA {
                results[index] = PackUpdate(
                    identifier: entry.identifier,
                    displayName: entry.displayName,
                    localSHA: entry.commitSHA,
                    remoteSHA: remoteSHA
                )
            }
        }

        return results.compactMap(\.self)
    }

    // MARK: - CLI Version Check

    /// Check if a newer mcs version is available via `git ls-remote --tags`.
    /// Returns nil if the repo is unreachable or no newer version exists.
    func checkCLIVersion(currentVersion: String) -> CLIUpdate? {
        let result = shell.run(
            environment.gitPath,
            arguments: ["ls-remote", "--tags", "--refs", Constants.MCSRepo.url],
            additionalEnvironment: Self.gitNoPromptEnv
        )

        guard result.succeeded,
              let latestTag = Self.parseLatestTag(from: result.stdout)
        else {
            return nil
        }

        guard VersionCompare.isNewer(candidate: latestTag, than: currentVersion) else {
            return nil
        }

        return CLIUpdate(currentVersion: currentVersion, latestVersion: latestTag)
    }

    // MARK: - Combined Check

    /// Run all enabled checks.
    /// - `forceRefresh: false` (default) — returns cached results if fresh (within 24h), otherwise network + cache
    /// - `forceRefresh: true` — always does network checks + updates cache (for explicit `mcs check-updates`)
    func performCheck(
        entries: [PackRegistryFile.PackEntry],
        forceRefresh: Bool = false,
        checkPacks: Bool,
        checkCLI: Bool
    ) -> CheckResult {
        // Serve cached results if still fresh (single disk read), unless explicitly forced
        if !forceRefresh, let cached = loadCache(),
           let lastCheck = ISO8601DateFormatter().date(from: cached.timestamp),
           Date().timeIntervalSince(lastCheck) < Self.cooldownInterval {
            return cached.result
        }

        let packUpdates = checkPacks ? checkPackUpdates(entries: entries) : []
        let cliUpdate = checkCLI ? checkCLIVersion(currentVersion: MCSVersion.current) : nil
        let result = CheckResult(packUpdates: packUpdates, cliUpdate: cliUpdate)

        // Always save to cache so the hook can serve fresh data between network checks
        saveCache(result)

        return result
    }

    // MARK: - Output Formatting

    /// Print update notices. Returns true if anything was printed.
    /// In hook mode, outputs structured JSON with `additionalContext` for Claude Code.
    /// In user mode, outputs colored terminal text.
    @discardableResult
    static func printResult(_ result: CheckResult, output: CLIOutput, isHook: Bool = false) -> Bool {
        guard !result.isEmpty else { return false }

        if isHook {
            // Structured JSON for Claude Code SessionStart hook
            let context = buildContextString(result)
            let hookOutput: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": Constants.HookEvent.sessionStart.rawValue,
                    "additionalContext": context,
                ] as [String: String],
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: hookOutput, options: [.sortedKeys])
                if let json = String(data: data, encoding: .utf8) {
                    print(json)
                }
            } catch {
                // Fallback to plain text if JSON serialization fails
                print(context)
            }
        } else {
            // User-invoked: colored output for terminal readability
            if let cli = result.cliUpdate {
                output.warn(
                    "mcs \(cli.latestVersion) available (current: \(cli.currentVersion)). "
                        + "Run 'brew upgrade \(Constants.MCSRepo.brewFormula)' to update."
                )
            }
            if !result.packUpdates.isEmpty {
                let noun = result.packUpdates.count == 1 ? "pack update" : "pack updates"
                output.info("\(result.packUpdates.count) \(noun) available:")
                for pack in result.packUpdates {
                    let local = String(pack.localSHA.prefix(7))
                    let remote = String(pack.remoteSHA.prefix(7))
                    output.plain("         \u{2022} \(pack.displayName) (\(local) \u{2192} \(remote))")
                }
                output.plain("       Run 'mcs pack update' to update.")
            }
        }

        return true
    }

    /// Build a context string for Claude from check results.
    /// Uses strong directive language to ensure Claude relays the notification visibly.
    private static func buildContextString(_ result: CheckResult) -> String {
        var lines: [String] = []
        lines.append(
            "STOP. Before doing ANY work, you MUST relay the following update notifications to the user."
                + " This is non-negotiable even if the user's message is a task request."
        )
        lines.append("")
        if let cli = result.cliUpdate {
            lines.append(
                "- New mcs version \(cli.latestVersion) is available (installed: \(cli.currentVersion))."
                    + " The user should run: brew upgrade \(Constants.MCSRepo.brewFormula)"
            )
        }
        if !result.packUpdates.isEmpty {
            let names = result.packUpdates.map(\.displayName).joined(separator: ", ")
            let noun = result.packUpdates.count == 1 ? "tech pack has" : "tech packs have"
            lines.append(
                "- \(result.packUpdates.count) \(noun) updates available: \(names)."
                    + " The user should run: mcs pack update"
            )
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Pack Filtering

    /// Resolve which pack IDs are relevant for update checks in the current context.
    /// Always includes globally-configured packs. If a project root is detected,
    /// also includes packs configured for that project.
    static func relevantPackIDs(environment: Environment) -> Set<String> {
        var ids = Set<String>()

        // Global packs — only load if the state file exists
        let fm = FileManager.default
        if fm.fileExists(atPath: environment.globalStateFile.path) {
            do {
                let globalState = try ProjectState(stateFile: environment.globalStateFile)
                ids.formUnion(globalState.configuredPacks)
            } catch {
                // Corrupt state — fall through to check all packs (safe fallback)
            }
        }

        // Project packs (detect from CWD)
        if let projectRoot = ProjectDetector.findProjectRoot() {
            let statePath = projectRoot
                .appendingPathComponent(Constants.FileNames.claudeDirectory)
                .appendingPathComponent(Constants.FileNames.mcsProject)
            if fm.fileExists(atPath: statePath.path) {
                do {
                    let projectState = try ProjectState(projectRoot: projectRoot)
                    ids.formUnion(projectState.configuredPacks)
                } catch {
                    // Corrupt state — fall through to check all packs (safe fallback)
                }
            }
        }

        return ids
    }

    /// Filter registry entries to only those relevant in the current context.
    static func filterEntries(
        _ entries: [PackRegistryFile.PackEntry],
        environment: Environment
    ) -> [PackRegistryFile.PackEntry] {
        let ids = relevantPackIDs(environment: environment)
        guard !ids.isEmpty else { return entries } // No state files → check all (first run)
        return entries.filter { ids.contains($0.identifier) }
    }

    // MARK: - Parsing Helpers

    /// Extract the SHA from the first line of `git ls-remote` output.
    /// Format: `<sha>\t<ref>\n`
    static func parseRemoteSHA(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        let sha = firstLine.split(separator: "\t", maxSplits: 1).first.map(String.init)
        guard let sha, !sha.isEmpty else { return nil }
        return sha
    }

    /// Find the latest CalVer tag from `git ls-remote --tags --refs` output.
    /// Each line: `<sha>\trefs/tags/<tag>\n`
    static func parseLatestTag(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var bestTag: String?

        for line in trimmed.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let refPath = String(parts[1])

            let prefix = "refs/tags/"
            guard refPath.hasPrefix(prefix) else { continue }
            let tag = String(refPath.dropFirst(prefix.count))

            guard VersionCompare.parse(tag) != nil else { continue }

            if let current = bestTag {
                if VersionCompare.isNewer(candidate: tag, than: current) {
                    bestTag = tag
                }
            } else {
                bestTag = tag
            }
        }

        return bestTag
    }
}

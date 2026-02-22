import Foundation

/// Manages the trust lifecycle for external packs — analyzing executable content,
/// prompting for user approval, and verifying script integrity before execution.
struct PackTrustManager: Sendable {
    let output: CLIOutput

    struct TrustDecision: Sendable {
        let approved: Bool
        let scriptHashes: [String: String] // relativePath -> SHA-256
    }

    // MARK: - Analyze

    /// Collect all executable content from a pack that needs trust approval.
    /// Returns items representing shell commands, scripts, and MCP server commands
    /// that will run with user privileges.
    func analyzeScripts(manifest: ExternalPackManifest, packPath: URL) throws -> [TrustableItem] {
        var items: [TrustableItem] = []

        // Component install actions
        if let components = manifest.components {
            for component in components {
                switch component.installAction {
                case .shellCommand(let command):
                    items.append(TrustableItem(
                        type: .shellCommand,
                        relativePath: nil,
                        content: command,
                        description: "\(component.displayName) — runs during install"
                    ))

                case .mcpServer(let config):
                    let serverDesc: String
                    if config.transport == .http, let url = config.url {
                        serverDesc = "\(config.name): \(url) (HTTP)"
                    } else {
                        let cmd = ([config.command ?? ""] + (config.args ?? [])).joined(separator: " ")
                        serverDesc = "\(config.name): \(cmd)"
                    }
                    items.append(TrustableItem(
                        type: .mcpServerCommand,
                        relativePath: nil,
                        content: serverDesc,
                        description: "MCP server — runs on every Claude Code session"
                    ))

                default:
                    break
                }

                // Doctor check scripts within components
                if let checks = component.doctorChecks {
                    for check in checks {
                        items += trustableItems(from: check, packPath: packPath)
                    }
                }
            }
        }

        // Configure project script
        if let configure = manifest.configureProject {
            let scriptFile = packPath.appendingPathComponent(configure.script)
            let content = try readFileContent(at: scriptFile, fallback: configure.script)
            items.append(TrustableItem(
                type: .configureScript,
                relativePath: configure.script,
                content: content,
                description: "Runs during project configuration"
            ))
        }

        // Supplementary doctor checks at the pack level
        if let checks = manifest.supplementaryDoctorChecks {
            for check in checks {
                items += trustableItems(from: check, packPath: packPath)
            }
        }

        // Hook contribution scripts
        if let hooks = manifest.hookContributions {
            for hook in hooks {
                let scriptFile = packPath.appendingPathComponent(hook.fragmentFile)
                let content = try readFileContent(at: scriptFile, fallback: hook.fragmentFile)
                items.append(TrustableItem(
                    type: .shellCommand,
                    relativePath: hook.fragmentFile,
                    content: content,
                    description: "Hook fragment injected into \(hook.hookName)"
                ))
            }
        }

        return items
    }

    // MARK: - Prompt

    /// Display all trustable items and prompt the user for approval.
    /// If the pack has no executable content, trust is implicit (returns approved with empty hashes).
    func promptForTrust(
        manifest: ExternalPackManifest,
        packPath: URL,
        items: [TrustableItem]
    ) throws -> TrustDecision {
        if items.isEmpty {
            return TrustDecision(approved: true, scriptHashes: [:])
        }

        output.plain("")
        output.header("Pack '\(manifest.displayName)' requests these permissions:")

        // Group items by type for display
        let shellCommands = items.filter { $0.type == .shellCommand && $0.relativePath == nil }
        let mcpServers = items.filter { $0.type == .mcpServerCommand }
        let scripts = items.filter { $0.relativePath != nil }

        if !shellCommands.isEmpty {
            output.plain("")
            output.sectionHeader("Shell Commands (run during install)")
            for item in shellCommands {
                output.plain("    \(item.content)")
            }
        }

        if !mcpServers.isEmpty {
            output.plain("")
            output.sectionHeader("MCP Servers (run on every Claude Code session)")
            for item in mcpServers {
                output.plain("    \(item.content)")
            }
        }

        if !scripts.isEmpty {
            output.plain("")
            output.sectionHeader("Scripts")
            for item in scripts {
                let lineCount = item.content.components(separatedBy: "\n").count
                let path = item.relativePath ?? "inline"
                output.plain("    \(path) (\(lineCount) lines) — \(item.description)")
            }
        }

        output.plain("")
        let approved = output.askYesNo("Trust this pack?", default: false)

        if approved {
            let hashes = try computeScriptHashes(items: items, packPath: packPath)
            return TrustDecision(approved: true, scriptHashes: hashes)
        }

        return TrustDecision(approved: false, scriptHashes: [:])
    }

    // MARK: - Verify

    /// Verify that trusted scripts haven't changed since they were approved.
    /// Returns relative paths of scripts that have been modified.
    func verifyTrust(
        trustedHashes: [String: String],
        packPath: URL
    ) -> [String] {
        var modified: [String] = []

        for (relativePath, expectedHash) in trustedHashes {
            let fileURL = packPath.appendingPathComponent(relativePath)
            guard let currentHash = try? Manifest.sha256(of: fileURL) else {
                // File missing or unreadable — treat as modified
                modified.append(relativePath)
                continue
            }
            if currentHash != expectedHash {
                modified.append(relativePath)
            }
        }

        return modified.sorted()
    }

    /// Check if an update introduces new scripts not in the trusted set.
    /// Returns items for scripts that are new or have changed.
    func detectNewScripts(
        currentHashes: [String: String],
        updatedPackPath: URL,
        manifest: ExternalPackManifest
    ) throws -> [TrustableItem] {
        let allItems = try analyzeScripts(manifest: manifest, packPath: updatedPackPath)

        // Filter to items with file paths that are new or changed
        return allItems.filter { item in
            guard let relativePath = item.relativePath else {
                // Non-file items (inline commands) — check if the content is new
                // by comparing against known commands; for safety, always flag them
                return true
            }
            guard let trustedHash = currentHashes[relativePath] else {
                return true // New script not in trusted set
            }
            let fileURL = updatedPackPath.appendingPathComponent(relativePath)
            guard let hash = try? Manifest.sha256(of: fileURL) else {
                return true // Can't hash — flag it
            }
            return hash != trustedHash // Changed since last trust
        }
    }

    // MARK: - Helpers

    private func readFileContent(at url: URL, fallback: String) throws -> String {
        if FileManager.default.fileExists(atPath: url.path) {
            return try String(contentsOf: url, encoding: .utf8)
        }
        return fallback
    }

    private func trustableItems(
        from check: ExternalDoctorCheckDefinition,
        packPath: URL
    ) -> [TrustableItem] {
        var items: [TrustableItem] = []

        if check.type == .shellScript, let command = check.command {
            // The command field may be a script file path or inline command
            let scriptFile = packPath.appendingPathComponent(command)
            let content: String
            if FileManager.default.fileExists(atPath: scriptFile.path),
               let fileContent = try? String(contentsOf: scriptFile, encoding: .utf8) {
                content = fileContent
                items.append(TrustableItem(
                    type: .doctorScript,
                    relativePath: command,
                    content: content,
                    description: "Doctor check script: \(check.name)"
                ))
            } else {
                items.append(TrustableItem(
                    type: .doctorScript,
                    relativePath: nil,
                    content: command,
                    description: "Doctor check command: \(check.name)"
                ))
            }
        }

        if let fixCommand = check.fixCommand {
            items.append(TrustableItem(
                type: .fixScript,
                relativePath: nil,
                content: fixCommand,
                description: "Fix command for: \(check.name)"
            ))
        }

        if let fixScript = check.fixScript {
            let scriptFile = packPath.appendingPathComponent(fixScript)
            let content: String
            if FileManager.default.fileExists(atPath: scriptFile.path),
               let fileContent = try? String(contentsOf: scriptFile, encoding: .utf8) {
                content = fileContent
            } else {
                content = fixScript
            }
            items.append(TrustableItem(
                type: .fixScript,
                relativePath: fixScript,
                content: content,
                description: "Fix script for: \(check.name)"
            ))
        }

        return items
    }

    /// Compute SHA-256 hashes for all script files referenced by trustable items.
    private func computeScriptHashes(
        items: [TrustableItem],
        packPath: URL
    ) throws -> [String: String] {
        var hashes: [String: String] = [:]

        for item in items {
            guard let relativePath = item.relativePath else { continue }
            let fileURL = packPath.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                hashes[relativePath] = try Manifest.sha256(of: fileURL)
            }
        }

        return hashes
    }
}

// MARK: - TrustableItem

/// An executable artifact within a pack that requires user trust approval.
struct TrustableItem: Sendable {
    let type: TrustableType
    let relativePath: String?  // For script files
    let content: String        // The actual content to display
    let description: String    // Human-readable description

    enum TrustableType: Sendable {
        case shellCommand      // From component install actions
        case configureScript   // From configureProject
        case doctorScript      // From shellScript doctor checks
        case fixScript         // From fix scripts / fix commands
        case mcpServerCommand  // MCP server command (runs with user privs)
    }
}

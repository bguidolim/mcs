import Foundation

/// Bridges an `ExternalPackManifest` (loaded from `techpack.yaml`) to the
/// `TechPack` protocol, making external packs indistinguishable from compiled-in
/// packs to the rest of the system (installer, doctor, configurator).
struct ExternalPackAdapter: TechPack {
    let manifest: ExternalPackManifest
    let packPath: URL

    // MARK: - TechPack Identity

    var identifier: String { manifest.identifier }
    var displayName: String { manifest.displayName }
    var description: String { manifest.description }

    // MARK: - Components

    var components: [ComponentDefinition] {
        guard let externalComponents = manifest.components else { return [] }
        return externalComponents.compactMap { ext in
            convertComponent(ext)
        }
    }

    // MARK: - Templates

    var templates: [TemplateContribution] {
        guard let externalTemplates = manifest.templates else { return [] }
        return externalTemplates.compactMap { ext in
            guard let content = try? readPackFile(ext.contentFile) else {
                return nil
            }
            return TemplateContribution(
                sectionIdentifier: ext.sectionIdentifier,
                templateContent: content,
                placeholders: ext.placeholders ?? []
            )
        }
    }

    // MARK: - Hook Contributions

    var hookContributions: [HookContribution] {
        guard let externalHooks = manifest.hookContributions else { return [] }
        return externalHooks.compactMap { ext in
            guard let fragment = try? readPackFile(ext.fragmentFile) else {
                return nil
            }
            return HookContribution(
                hookName: ext.hookName,
                scriptFragment: fragment,
                position: ext.position?.hookPosition ?? .after
            )
        }
    }

    // MARK: - Gitignore Entries

    var gitignoreEntries: [String] {
        manifest.gitignoreEntries ?? []
    }

    // MARK: - Doctor Checks

    var supplementaryDoctorChecks: [any DoctorCheck] {
        guard let externalChecks = manifest.supplementaryDoctorChecks else { return [] }
        let shell = ShellRunner(environment: Environment())
        let output = CLIOutput()
        let scriptRunner = ScriptRunner(shell: shell, output: output)

        return externalChecks.compactMap { ext in
            convertDoctorCheck(ext, scriptRunner: scriptRunner)
        }
    }

    // MARK: - Migrations

    var migrations: [any PackMigration] { [] }

    // MARK: - Template Values (Prompt Execution)

    func templateValues(context: ProjectConfigContext) -> [String: String] {
        guard let prompts = manifest.prompts, !prompts.isEmpty else { return [:] }
        let shell = ShellRunner(environment: Environment())
        let scriptRunner = ScriptRunner(shell: shell, output: context.output)
        let executor = PromptExecutor(output: context.output, scriptRunner: scriptRunner)

        do {
            return try executor.executeAll(
                prompts: prompts,
                packPath: packPath,
                projectPath: context.projectPath
            )
        } catch {
            context.output.warn("Failed to resolve template values: \(error.localizedDescription)")
            return [:]
        }
    }

    // MARK: - Project Configuration

    func configureProject(at path: URL, context: ProjectConfigContext) throws {
        guard let configure = manifest.configureProject else { return }

        let shell = ShellRunner(environment: Environment())
        let scriptRunner = ScriptRunner(shell: shell, output: context.output)
        let scriptURL = packPath.appendingPathComponent(configure.script)

        // Build env vars from resolved template values
        var env: [String: String] = [:]
        env["MCS_PROJECT_PATH"] = path.path
        for (key, value) in context.resolvedValues {
            env["MCS_RESOLVED_\(key.uppercased())"] = value
        }

        let result = try scriptRunner.run(
            script: scriptURL,
            packPath: packPath,
            environmentVars: env,
            workingDirectory: path.path,
            timeout: 60
        )

        if !result.succeeded {
            context.output.warn("Configure script failed: \(result.stderr)")
        }
    }

    // MARK: - File Reading

    /// Read a file from the pack checkout directory. Validates path containment.
    private func readPackFile(_ relativePath: String) throws -> String {
        let fileURL = packPath.appendingPathComponent(relativePath)
        let resolved = fileURL.standardizedFileURL.path
        let packPrefix = packPath.standardizedFileURL.path.hasSuffix("/")
            ? packPath.standardizedFileURL.path
            : packPath.standardizedFileURL.path + "/"

        guard resolved.hasPrefix(packPrefix) || resolved == packPath.standardizedFileURL.path else {
            throw PackAdapterError.pathTraversal(relativePath)
        }

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    // MARK: - Component Conversion

    private func convertComponent(_ ext: ExternalComponentDefinition) -> ComponentDefinition? {
        guard let action = convertInstallAction(ext.installAction) else { return nil }

        let supplementary: [any DoctorCheck]
        if let checks = ext.doctorChecks {
            let shell = ShellRunner(environment: Environment())
            let output = CLIOutput()
            let scriptRunner = ScriptRunner(shell: shell, output: output)
            supplementary = checks.compactMap { convertDoctorCheck($0, scriptRunner: scriptRunner) }
        } else {
            supplementary = []
        }

        return ComponentDefinition(
            id: ext.id,
            displayName: ext.displayName,
            description: ext.description,
            type: ext.type.componentType,
            packIdentifier: manifest.identifier,
            dependencies: ext.dependencies ?? [],
            isRequired: ext.isRequired ?? false,
            installAction: action,
            supplementaryChecks: supplementary
        )
    }

    private func convertInstallAction(_ ext: ExternalInstallAction) -> ComponentInstallAction? {
        switch ext {
        case .mcpServer(let config):
            return .mcpServer(config.toMCPServerConfig())

        case .plugin(let name):
            return .plugin(name: name)

        case .brewInstall(let package):
            return .brewInstall(package: package)

        case .shellCommand(let command):
            return .shellCommand(command: command)

        case .gitignoreEntries(let entries):
            return .gitignoreEntries(entries: entries)

        case .settingsMerge:
            return .settingsMerge

        case .settingsFile:
            // settingsFile is a future feature — for now treat as settingsMerge
            return .settingsMerge

        case .copyPackFile(let config):
            let sourceURL = packPath.appendingPathComponent(config.source)
            let fileType: CopyFileType
            switch config.fileType ?? .generic {
            case .skill: fileType = .skill
            case .hook: fileType = .hook
            case .command: fileType = .command
            case .generic: fileType = .generic
            }
            return .copyPackFile(
                source: sourceURL,
                destination: config.destination,
                fileType: fileType
            )
        }
    }

    // MARK: - Doctor Check Conversion

    private func convertDoctorCheck(
        _ ext: ExternalDoctorCheckDefinition,
        scriptRunner: ScriptRunner
    ) -> (any DoctorCheck)? {
        let projectRoot = ProjectDetector.findProjectRoot()
        return ExternalDoctorCheckFactory.makeCheck(
            from: ext,
            packPath: packPath,
            projectRoot: projectRoot,
            scriptRunner: scriptRunner
        )
    }
}

// MARK: - Errors

enum PackAdapterError: Error, Equatable, Sendable, LocalizedError {
    case pathTraversal(String)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .pathTraversal(let path):
            return "Path traversal attempt: '\(path)' escapes pack directory"
        case .fileNotFound(let path):
            return "File not found in pack: '\(path)'"
        }
    }
}

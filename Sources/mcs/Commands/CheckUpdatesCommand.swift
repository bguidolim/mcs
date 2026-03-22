import ArgumentParser
import Foundation

struct CheckUpdatesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check-updates",
        abstract: "Check for tech pack and CLI updates"
    )

    @Flag(name: .long, help: "Bypass the 7-day cooldown")
    var force: Bool = false

    @Flag(name: .long, help: "Output results as JSON")
    var json: Bool = false

    func run() throws {
        let env = Environment()
        let output = CLIOutput()
        let shell = ShellRunner(environment: env)
        let config = MCSConfig.load(from: env.mcsConfigFile)

        let registry = PackRegistryFile(path: env.packsRegistry)
        let registryData: PackRegistryFile.RegistryData
        do {
            registryData = try registry.load()
        } catch {
            registryData = PackRegistryFile.RegistryData()
        }

        // When config is unconfigured, default to checking both
        let checkPacks = config.updateCheckPacks ?? true
        let checkCLI = config.updateCheckCLI ?? true

        let relevantEntries = UpdateChecker.filterEntries(registryData.packs, environment: env)

        let checker = UpdateChecker(environment: env, shell: shell)
        let result = checker.performCheck(
            entries: relevantEntries,
            force: force,
            checkPacks: checkPacks,
            checkCLI: checkCLI
        )

        if json {
            printJSON(result)
        } else {
            UpdateChecker.printHumanReadable(result, output: output)
        }
    }

    private func printJSON(_ result: UpdateChecker.CheckResult) {
        var dict: [String: Any] = [:]

        var cliDict: [String: Any] = [
            "current": MCSVersion.current,
            "updateAvailable": result.cliUpdate != nil,
        ]
        if let cli = result.cliUpdate {
            cliDict["latest"] = cli.latestVersion
        }
        dict["cli"] = cliDict

        dict["packs"] = result.packUpdates.map { update in
            [
                "identifier": update.identifier,
                "displayName": update.displayName,
                "localSHA": update.localSHA,
                "remoteSHA": update.remoteSHA,
            ] as [String: String]
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]
        ), let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    }
}

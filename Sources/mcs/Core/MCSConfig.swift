import Foundation
import Yams

/// User preferences stored at `~/.mcs/config.yaml`.
/// All fields are optional — `nil` means "never configured".
struct MCSConfig: Codable {
    var updateCheckPacks: Bool?
    var updateCheckCLI: Bool?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case updateCheckPacks = "update-check-packs"
        case updateCheckCLI = "update-check-cli"
    }

    /// Whether any update check is enabled (at least one key is true).
    var isUpdateCheckEnabled: Bool {
        (updateCheckPacks ?? false) || (updateCheckCLI ?? false)
    }

    /// Whether neither key has been configured yet (first-run state).
    var isUnconfigured: Bool {
        updateCheckPacks == nil && updateCheckCLI == nil
    }

    // MARK: - Known Keys

    struct ConfigKey {
        let key: String
        let description: String
        let defaultValue: String
    }

    static let knownKeys: [ConfigKey] = [
        ConfigKey(
            key: CodingKeys.updateCheckPacks.rawValue,
            description: "Automatically check for tech pack updates on Claude Code session start",
            defaultValue: "false"
        ),
        ConfigKey(
            key: CodingKeys.updateCheckCLI.rawValue,
            description: "Automatically check for new mcs versions on Claude Code session start",
            defaultValue: "false"
        ),
    ]

    // MARK: - Persistence

    /// Load config from disk. Returns empty config if file is missing.
    /// Warns via `output` if the file exists but is corrupt.
    static func load(from path: URL, output: CLIOutput? = nil) -> MCSConfig {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path.path) else { return MCSConfig() }

        let content: String
        do {
            content = try String(contentsOf: path, encoding: .utf8)
        } catch {
            output?.warn("Could not read config file: \(error.localizedDescription)")
            return MCSConfig()
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return MCSConfig()
        }

        do {
            return try YAMLDecoder().decode(MCSConfig.self, from: content)
        } catch {
            output?.warn("Config file is corrupt (\(path.lastPathComponent)): \(error.localizedDescription)")
            return MCSConfig()
        }
    }

    /// Save config to disk, creating parent directories if needed.
    func save(to path: URL) throws {
        let fm = FileManager.default
        let dir = path.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let yaml = try YAMLEncoder().encode(self)
        try yaml.write(to: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Key Access

    /// Get a config value by key name. Returns nil if the key is unknown or unset.
    func value(forKey key: String) -> Bool? {
        switch key {
        case CodingKeys.updateCheckPacks.rawValue: updateCheckPacks
        case CodingKeys.updateCheckCLI.rawValue: updateCheckCLI
        default: nil
        }
    }

    /// Set a config value by key name. Returns false if the key is unknown.
    mutating func setValue(_ value: Bool, forKey key: String) -> Bool {
        switch key {
        case CodingKeys.updateCheckPacks.rawValue:
            updateCheckPacks = value
            return true
        case CodingKeys.updateCheckCLI.rawValue:
            updateCheckCLI = value
            return true
        default:
            return false
        }
    }
}

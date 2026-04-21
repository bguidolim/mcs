import Foundation

/// Collects prompt definitions from multiple packs, identifies shared keys,
/// and executes shared prompts once with a combined display showing each pack's label.
///
/// Only `input` and `select` prompt types are eligible for deduplication.
/// `script` and `fileDetect` types are pack-specific and always run per-pack.
enum CrossPackPromptResolver {
    /// A prompt definition paired with the pack that declares it.
    struct PackPromptInfo {
        let packName: String
        let prompt: PromptDefinition
    }

    /// Prompt types eligible for cross-pack deduplication.
    static let deduplicableTypes: Set<PromptType> = [.input, .select]

    /// Flat list of every declaration from every pack. Multiple packs can declare
    /// the same key — `partitionDeclaredPrompts` groups them when merging select options.
    static func collectDeclaredPrompts(
        packs: [any TechPack],
        context: ProjectConfigContext
    ) -> [PromptDefinition] {
        packs.flatMap { $0.declaredPrompts(context: context) }
    }

    /// Partition declared prompts against `priorValues`.
    ///
    /// `script` and `fileDetect` keys are excluded from both outputs — they always
    /// re-run and must not trigger the "new prompts" UX branch.
    ///
    /// Select priors are reusable when:
    /// - no declaration constrains the value (all have nil/empty options — the executor
    ///   falls back to free-form input), OR
    /// - at least one declaration constrains via `options` AND the prior is in the
    ///   merged set of constrained options.
    ///
    /// Conservative rule for mixed declarations: when any pack constrains the value,
    /// the prior must satisfy those constraints (matches `resolveSharedPrompts` which
    /// presents the merged constrained option list to the user).
    ///
    /// Type conflicts across packs (input vs select) fall back to input semantics.
    static func partitionDeclaredPrompts(
        _ prompts: [PromptDefinition],
        priorValues: [String: String]
    ) -> (reusableValues: [String: String], newDeclaredKeys: Set<String>) {
        var constrainedOptionsByKey: [String: Set<String>] = [:]
        var typesByKey: [String: Set<PromptType>] = [:]
        for prompt in prompts {
            typesByKey[prompt.key, default: []].insert(prompt.type)
            if prompt.type == .select, let options = prompt.options, !options.isEmpty {
                constrainedOptionsByKey[prompt.key, default: []].formUnion(options.map(\.value))
            }
        }

        var reusable: [String: String] = [:]
        var newKeys: Set<String> = []
        for (key, types) in typesByKey {
            let answerableTypes = types.intersection(deduplicableTypes)
            guard !answerableTypes.isEmpty else { continue }

            guard let prior = priorValues[key] else {
                newKeys.insert(key)
                continue
            }

            if answerableTypes == [.select] {
                let constrained = constrainedOptionsByKey[key] ?? []
                // No constraints → free-form; any constraint → prior must satisfy it.
                if constrained.isEmpty || constrained.contains(prior) {
                    reusable[key] = prior
                } else {
                    newKeys.insert(key)
                }
            } else {
                reusable[key] = prior
            }
        }
        return (reusable, newKeys)
    }

    /// Collect prompts from all packs and group by key, skipping already-resolved keys.
    ///
    /// - Returns: A dictionary keyed by prompt key, with each value being the list
    ///   of packs that declare that key (only for deduplicable types, 2+ packs).
    static func groupSharedPrompts(
        packs: [any TechPack],
        context: ProjectConfigContext
    ) -> [String: [PackPromptInfo]] {
        var byKey: [String: [PackPromptInfo]] = [:]
        let alreadyResolved = Set(context.resolvedValues.keys)

        for pack in packs {
            for prompt in pack.declaredPrompts(context: context) {
                guard deduplicableTypes.contains(prompt.type) else { continue }
                guard !alreadyResolved.contains(prompt.key) else { continue }
                byKey[prompt.key, default: []].append(
                    PackPromptInfo(packName: pack.displayName, prompt: prompt)
                )
            }
        }

        // Only return keys shared by 2+ packs
        return byKey.filter { $0.value.count > 1 }
    }

    /// Execute shared prompts once, showing a combined label from all packs.
    ///
    /// - Parameter priorValues: Values from a previous sync; used as the default
    ///   when present, overriding pack-declared defaults. For `select` prompts,
    ///   a prior value only applies when it still matches a merged option.
    /// - Returns: Resolved values for all shared prompt keys.
    static func resolveSharedPrompts(
        _ shared: [String: [PackPromptInfo]],
        output: CLIOutput,
        priorValues: [String: String] = [:]
    ) -> [String: String] {
        var resolved: [String: String] = [:]

        for key in shared.keys.sorted() {
            guard let infos = shared[key], !infos.isEmpty else { continue }

            // Display combined prompt header
            let packNames = infos.map(\.packName).joined(separator: ", ")
            output.plain("")
            output.info("\(key) (shared by \(packNames))")

            for info in infos {
                let label = info.prompt.label ?? "(no description)"
                output.dimmed("  \(info.packName): \"\(label)\"")
            }

            // Resolve based on the first prompt's type; warn on type conflicts
            let primaryType = infos[0].prompt.type
            let hasTypeConflict = infos.contains { $0.prompt.type != primaryType }
            if hasTypeConflict {
                let typesByPack = infos.map { "\($0.packName): \($0.prompt.type.rawValue)" }.joined(separator: ", ")
                output.warn("  Type conflict across packs (\(typesByPack)) — falling back to text input")
            }

            // Prior value wins over pack-declared defaults; fall back to first non-nil declared default
            let declaredDefault = infos.compactMap(\.prompt.defaultValue).first
            let prior = priorValues[key]

            if !hasTypeConflict, primaryType == .select {
                // Merge unique options from all packs (first occurrence of each value wins)
                var seenValues = Set<String>()
                var mergedOptions: [PromptOption] = []
                for info in infos {
                    for option in info.prompt.options ?? []
                        where seenValues.insert(option.value).inserted {
                        mergedOptions.append(option)
                    }
                }
                guard !mergedOptions.isEmpty else {
                    output.warn("  Shared select prompt '\(key)' has no options — using default value")
                    resolved[key] = prior ?? declaredDefault ?? ""
                    continue
                }
                let items = mergedOptions.map { (name: $0.label, description: $0.value) }
                let label = "Select value for \(key)"
                let initialIndex = PromptOption.index(of: prior, in: mergedOptions)
                let selected = output.singleSelect(title: label, items: items, initialIndex: initialIndex)
                resolved[key] = mergedOptions[selected].value
            } else {
                // Default to text input; prior value seeds the Enter-to-accept default
                let effectiveDefault = prior ?? declaredDefault
                let value = output.promptInline("  Enter value for \(key)", default: effectiveDefault)
                resolved[key] = value
            }
        }

        return resolved
    }
}

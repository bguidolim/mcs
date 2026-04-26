# CLI Reference

Complete command reference for `mcs`. For a quick introduction, see the [README](../README.md#-quick-start).

## `mcs sync`

The primary command. Configures a project by selecting packs and installing their artifacts. Running without flags opens interactive multi-select.

```bash
mcs sync [path]                  # Interactive project sync (default command)
mcs sync --pack <name>           # Non-interactive: apply specific pack(s) (repeatable)
mcs sync --all                   # Apply all registered packs without prompts
mcs sync --dry-run               # Preview what would change
mcs sync --customize             # Per-pack component selection
mcs sync --global                # Install to global scope (~/.claude/)
mcs sync --lock                  # Checkout locked versions from mcs.lock.yaml
mcs sync --update                # Fetch latest and write/update mcs.lock.yaml (opt-in)
```

| Flag | Description |
|------|-------------|
| `[path]` | Project directory (defaults to current directory) |
| `--pack <name>` | Apply a specific pack non-interactively. Repeatable for multiple packs. |
| `--all` | Apply all registered packs without interactive selection. |
| `--dry-run` | Preview changes without writing any files. |
| `--customize` | Per-pack component selection (deselect individual components). |
| `--global` | Sync global-scope components (brew packages, plugins, MCP servers to `~/.claude/`). |
| `--lock` | Check out the commits pinned in `mcs.lock.yaml`. |
| `--update` | Fetch latest pack versions and write/update `mcs.lock.yaml`. Lockfile generation is opt-in; this flag forces a write for the current run regardless of the `generate-lockfile` config. |

`mcs sync` is also the default command — running `mcs` alone is equivalent to `mcs sync`.

## `mcs pack`

Manage registered tech packs.

### `mcs pack add <source>`

Add a tech pack from a git URL, GitHub shorthand, or local path.

```bash
mcs pack add <source>            # Git URL, GitHub shorthand, or local path
mcs pack add user/repo           # GitHub shorthand → https://github.com/user/repo.git
mcs pack add /path/to/pack       # Local pack (read in-place, no clone)
mcs pack add <url> --ref <tag>   # Pin to a specific tag, branch, or commit
mcs pack add <url> --preview     # Preview pack contents without installing
```

| Flag | Description |
|------|-------------|
| `--ref <tag>` | Pin to a specific git tag, branch, or commit (git packs only). |
| `--preview` | Preview the pack's contents without installing. |

Source resolution order: URL schemes → filesystem paths → GitHub shorthand.

### `mcs pack remove <name>`

Remove a registered pack.

```bash
mcs pack remove <name>           # Remove with confirmation
mcs pack remove <name> --force   # Remove without confirmation
```

Removal is federated: `mcs` discovers all projects using the pack (via the project index) and runs convergence cleanup for each scope.

### `mcs pack list`

```bash
mcs pack list                    # List registered packs with status
```

### `mcs pack update [name]`

```bash
mcs pack update [name]           # Update pack(s) to latest version
```

Fetches the latest commits from the remote and updates the local checkout. Local packs are skipped (they are read in-place and pick up changes automatically).

### `mcs pack validate [source]`

Validate a tech pack for structural correctness and best practices. Designed for pack authors to catch issues locally before submitting to the registry.

```bash
mcs pack validate                # Validate pack in current directory
mcs pack validate /path/to/pack  # Validate pack at a specific path
mcs pack validate ios            # Validate an installed pack by identifier
```

| Argument | Description |
|----------|-------------|
| `[source]` | Directory path or installed pack identifier. Defaults to current directory. |

**Two-stage validation pipeline:**

1. **Structural validation** — manifest existence, YAML parsing, schema validation, `minMCSVersion` check, referenced file existence
2. **Heuristic checks** — best-practice analysis with severity levels

**Severity levels:**

| Severity | Exit code | Examples |
|----------|-----------|---------|
| Error | 1 | Empty pack (no components/templates/configure), `source: "."` copying entire pack root, missing settings file sources |
| Warning | 0 | Unreferenced files in subdirectories, unreferenced root-level content files, MCP server using python/node without brew component, missing python module directory |

Structural errors always cause exit code 1 and stop further analysis. Heuristic errors also cause exit code 1. Warnings are advisory and do not affect the exit code.

When unreferenced-file warnings appear, the command also emits a remediation hint pointing authors at the manifest's `ignore:` field (see [Schema Reference](techpack-schema.md#the-ignore-field)) — adding intentional non-material paths there silences both the validation warnings and downstream `mcs check-updates` notifications for commits limited to those paths.

## `mcs doctor`

Diagnose installation health with multi-layer checks.

```bash
mcs doctor                       # Diagnose all packs (project + global)
mcs doctor --fix                 # Diagnose and auto-fix issues
mcs doctor --pack <name>         # Check a specific pack only
mcs doctor --global              # Check globally-configured packs only
```

| Flag | Description |
|------|-------------|
| `--fix` | Auto-fix issues where possible (re-add gitignore entries, create missing state files, etc.). |
| `-y, --yes` | Skip confirmation prompt before applying fixes (use with `--fix`). |
| `--pack <name>` | Only check a specific pack. |
| `--global` | Only check globally-configured packs. |

Doctor resolves packs from: explicit `--pack` flag → project `.mcs-project` state → `CLAUDE.local.md` section markers → global manifest.

## `mcs cleanup`

Find and delete timestamped backup files created during sync.

```bash
mcs cleanup                      # List backups and confirm before deleting
mcs cleanup --force              # Delete backups without confirmation
```

## `mcs export`

Export your current Claude Code configuration as a reusable tech pack.

```bash
mcs export <dir>                 # Export current config as a tech pack
mcs export <dir> --global        # Export global scope (~/.claude/)
mcs export <dir> --identifier id # Set pack identifier (prompted if omitted)
mcs export <dir> --non-interactive  # Include everything without prompts
mcs export <dir> --dry-run       # Preview what would be exported
```

| Flag | Description |
|------|-------------|
| `<dir>` | Output directory for the generated pack. |
| `--global` | Export global scope (`~/.claude/`) instead of the current project. |
| `--identifier id` | Set the pack identifier (prompted interactively if omitted). |
| `--non-interactive` | Include all discovered artifacts without prompting for selection. |
| `--dry-run` | Preview what would be exported without writing files. |

The export wizard discovers MCP servers, hooks, skills, commands, agents, plugins, `CLAUDE.md` sections, gitignore entries (global only), and settings. Sensitive env vars are replaced with `__PLACEHOLDER__` tokens and corresponding `prompts:` entries are generated.

## `mcs check-updates`

Check for available tech pack and CLI updates. Designed to be lightweight and non-intrusive.

```bash
mcs check-updates                # Check for updates (always fetches from remote)
mcs check-updates --hook         # Run as SessionStart hook (respects 24-hour cooldown and config)
mcs check-updates --json         # Machine-readable JSON output
```

| Flag | Description |
|------|-------------|
| `--hook` | Run as a Claude Code SessionStart hook. Respects the 24-hour cooldown and config keys. Without this flag, always fetches from remote. |
| `--json` | Output results as JSON instead of human-readable text. |

**How it works:**
- **Pack checks**: Runs `git ls-remote` per pack to compare the remote HEAD against the local commit SHA. Local packs are skipped.
- **Noise filter**: When the remote SHA differs, runs a shallow `git fetch` + `git diff --name-only` in the local pack clone and classifies the changed-path list. If every path is deny-listed infrastructure (README, LICENSE, CHANGELOG, `.github/`, `node_modules/`, `.build/`, `Makefile`, `.gitignore`, etc.), the notification is suppressed and `~/.mcs/registry.yaml`'s `commitSHA` advances to the new remote SHA — the same infrastructure-only commits won't re-trigger on future cooldown windows. Any non-deny-listed path makes the update material and surfaces the notification.
- **`techpack.yaml` always surfaces**: manifest edits can change the install surface entirely (new hook scripts, swapped MCP server commands, different component actions), so the filter never suppresses a commit that touches the manifest — supply-chain safety takes precedence over noise reduction.
- **Never-hide on filter failure**: if `git fetch` or `git diff` errors (offline, access revoked, repo corrupt), the notification surfaces unfiltered. The filter can only suppress; it can't manufacture silence on error.
- **CLI version check**: Queries `git ls-remote --tags` on the mcs repository and compares the latest CalVer tag against the installed version.
- **Cache**: Results are cached in `~/.mcs/update-check.json` (timestamp + results). Cached results are served if less than 24 hours old (no network request). When the cache is stale, a fresh network check runs and the results are cached. `mcs check-updates` (without `--hook`) always forces a fresh check; `mcs sync` and `mcs doctor` respect the cache.
- **Cache invalidation**: `mcs pack update` deletes the cache so the next hook re-checks. CLI version cache self-invalidates when the user upgrades mcs.
- **Scope**: Checks global packs plus packs configured in the current project (detected via project root). Packs not relevant to the current context are skipped.
- **Offline resilience**: Network failures are silently ignored — the command never errors on connectivity issues.

**Note:** `mcs sync` and `mcs doctor` check for updates at the end of execution, respecting the 24-hour cache. The config keys below only control the **automatic** `SessionStart` hook that runs when you start a Claude Code session.

## `mcs config`

Manage mcs user preferences stored at `~/.mcs/config.yaml`.

```bash
mcs config list                  # Show all settings with current values
mcs config get <key>             # Get a specific value
mcs config set <key> <value>     # Set a value (true/false)
```

### Available Keys

| Key | Description | Default |
|-----|-------------|---------|
| `update-check-packs` | Automatically check for tech pack updates on session start | `false` |
| `update-check-cli` | Automatically check for new mcs versions on session start | `false` |

These keys control a `SessionStart` hook in `~/.claude/settings.json` that runs `mcs check-updates` when you start a Claude Code session. The hook's output is injected into Claude's context so Claude can inform you about available updates.

- **Enabled (either key `true`)**: A synchronous `SessionStart` hook is registered. It respects the 24-hour cooldown.
- **Disabled (both keys `false`)**: No hook is registered. You can still check manually with `mcs check-updates` or rely on `mcs sync` / `mcs doctor` which check using the 24-hour cache.

When either key changes, `mcs config set` immediately adds or removes the hook from `~/.claude/settings.json` — no re-sync needed. The same hook is also converged during `mcs sync`.

On first interactive sync, `mcs` prompts whether to enable automatic update notifications (sets both keys at once). Fine-tune later with `mcs config set`.

---

**Next**: Learn to build packs from scratch in [Creating Tech Packs](creating-tech-packs.md).

---

[Home](README.md) | [CLI Reference](cli.md) | [Creating Tech Packs](creating-tech-packs.md) | [Schema](techpack-schema.md) | [Architecture](architecture.md) | [Troubleshooting](troubleshooting.md)

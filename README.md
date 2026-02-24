# My Claude Setup (`mcs`)

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)]()
[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)]()
[![Homebrew Tap](https://img.shields.io/badge/homebrew-tap-yellow.svg)]()

> [!WARNING]
> **This project is under active development.** Expect breaking changes, bugs, and incomplete features. Migrations between versions are not guaranteed. Use at your own risk.

A configuration engine for Claude Code. Package your MCP servers, plugins, hooks, skills, commands, and settings into shareable **tech packs** — then install, configure, and maintain them across projects and machines.

```bash
brew install bguidolim/tap/my-claude-setup
mcs pack add https://github.com/you/your-pack
mcs configure
```

---

## What Is `mcs`?

`mcs` is a pure engine — it ships **zero bundled content**. All features come from external tech packs: Git repositories with a `techpack.yaml` manifest describing what to install and how to configure it.

You add packs. The engine handles the rest:

- **Install** dependencies, MCP servers, and plugins
- **Configure** per-project artifacts (hooks, skills, commands, templates, settings)
- **Verify** everything with `mcs doctor`
- **Converge** to the desired state on re-run (add, update, or remove packs cleanly)

Think of it as **Terraform for your Claude Code environment**.

---

## Why Use `mcs`?

| | Capability | Why it matters |
|---|------------|---------------|
| 📦 | **Tech Packs** | Share your Claude setup as a Git repo anyone can install |
| 🔄 | **Convergent** | Re-run safely — adds what's missing, removes what's deselected, updates what changed |
| 🩺 | **Self-Healing** | `mcs doctor --fix` detects and repairs configuration drift |
| 🎯 | **Per-Project** | Each project gets its own hooks, skills, commands, templates, and settings |
| 🌍 | **Portable** | Recreate your entire Claude environment on a new machine in minutes |
| 🔒 | **Safe** | Backups before writes, section markers for managed content, dry-run previews |

### Manual Setup vs `mcs`

| Manual Claude Code Setup | With `mcs` |
|--------------------------|------------|
| Install MCP servers one by one | `mcs pack add` + `mcs configure` |
| Hand-edit `settings.json` | Managed, non-destructive settings composition |
| Copy hooks between projects | Auto-installed per-project from packs |
| Configuration drifts over time | `mcs doctor --fix` repairs drift |
| Rebuild from memory on new machine | Fully reproducible in minutes |
| No way to share your setup | Push a tech pack, others `mcs pack add` it |

---

## Quick Start

```bash
# Install mcs
brew install bguidolim/tap/my-claude-setup

# Add a tech pack
mcs pack add https://github.com/you/your-pack

# Install global components (brew packages, plugins)
mcs install

# Configure a project
cd ~/Developer/my-project
mcs configure

# Verify everything
mcs doctor
```

<details>
<summary><strong>Prerequisites</strong></summary>

- macOS (Apple Silicon or Intel)
- Xcode Command Line Tools
  ```bash
  xcode-select --install
  ```
- Claude Code CLI (`claude`)

</details>

---

## How It Works

```
mcs pack add <url>      → Register a tech pack from a Git repo
mcs pack list           → See registered packs
mcs install             → Install global components (brew, plugins)
mcs configure [path]    → Per-project setup: select packs, install artifacts
mcs doctor [--fix]      → Diagnose and repair configuration
mcs cleanup             → Remove stale backup files
```

### Per-Project Artifacts

When you run `mcs configure` in a project, the engine:

1. Lets you select which packs to apply
2. Resolves prompts (detects project files, asks for config values)
3. Installs per-project artifacts:

| Artifact | Location |
|----------|----------|
| MCP servers | `~/.claude.json` (per-project scope) |
| Skills | `<project>/.claude/skills/` |
| Hooks | `<project>/.claude/hooks/` |
| Commands | `<project>/.claude/commands/` |
| Settings | `<project>/.claude/settings.local.json` |
| Templates | `<project>/CLAUDE.local.md` |

4. Tracks everything in `<project>/.claude/.mcs-project` for clean convergence

Re-running `mcs configure` converges to the desired state — new packs are added, deselected packs are fully cleaned up, unchanged packs are updated idempotently.

---

## Tech Packs

A tech pack is a Git repository with a `techpack.yaml` file. It can include any combination of:

- **Brew packages** — CLI dependencies
- **MCP servers** — stdio or HTTP transport
- **Plugins** — Claude Code plugins
- **Hooks** — session lifecycle scripts (SessionStart, PreToolUse, etc.)
- **Skills** — domain knowledge and workflows
- **Commands** — custom `/slash` commands
- **Templates** — CLAUDE.local.md instructions with placeholder substitution
- **Settings** — merged into `settings.local.json`
- **Doctor checks** — health verification and auto-repair

### Example Pack

```yaml
schemaVersion: 1
identifier: my-pack
displayName: My Development Pack
description: My Claude Code setup
version: "1.0.0"

components:
  - id: node
    description: JavaScript runtime
    brew: node

  - id: my-server
    description: Code analysis MCP server
    dependencies: [node]
    mcp:
      command: npx
      args: ["-y", "my-server@latest"]

  - id: pr-review
    description: PR review agents
    plugin: "pr-review-toolkit@claude-plugins-official"

  - id: session-hook
    description: Git status on session start
    hookEvent: SessionStart
    hook:
      source: hooks/session_start.sh
      destination: session_start.sh

  - id: settings
    description: Plan mode and thinking
    isRequired: true
    settingsFile: config/settings.json

templates:
  - sectionIdentifier: my-pack.instructions
    contentFile: templates/instructions.md
```

### Creating Your Own Pack

```bash
mkdir my-pack && cd my-pack && git init
# Write your techpack.yaml
git add -A && git commit -m "Initial pack"
git remote add origin https://github.com/you/my-pack.git
git push -u origin main

# Install it
mcs pack add https://github.com/you/my-pack
```

Full guide: [Creating Tech Packs](docs/creating-tech-packs.md)

Schema reference: [Tech Pack Schema](docs/techpack-schema.md)

---

## Safety Guarantees

| Guarantee | Meaning |
|-----------|---------|
| Backups | Timestamped backup before modifying files with user content |
| Dry Run | `--dry-run` previews changes without applying them |
| Selective Install | Choose components with `--customize` or install all |
| Idempotent | Safe to re-run at any time |
| Non-Destructive | User content in CLAUDE.local.md preserved via section markers |
| Convergent | Deselected packs are fully cleaned up |
| Trust Verification | Pack scripts are hashed at add-time, verified at load-time |

---

## Commands Reference

```bash
# Pack management
mcs pack add <url>               # Add a tech pack from a Git URL
mcs pack remove <name>           # Remove a registered pack
mcs pack list                    # List registered packs
mcs pack update [name]           # Update pack(s) to latest

# Installation
mcs install                      # Interactive global component install
mcs install --all                # Install everything from all packs
mcs install --dry-run            # Preview what would be installed

# Project configuration
mcs configure [path]             # Per-project setup with pack selection
mcs configure --pack <name>      # Non-interactive: apply specific pack(s)

# Health checks
mcs doctor                       # Diagnose installation health
mcs doctor --fix                 # Diagnose and auto-fix issues
mcs doctor --pack <name>         # Check a specific pack only

# Maintenance
mcs cleanup                      # Find and delete backup files
mcs cleanup --force              # Delete backups without confirmation
```

---

## Troubleshooting

Start with:

```bash
mcs doctor
```

Auto-repair:

```bash
mcs doctor --fix
```

Full guide: [`docs/troubleshooting.md`](docs/troubleshooting.md)

---

## Development

```bash
swift build
swift test
swift build -c release --arch arm64 --arch x86_64   # Universal binary
```

See [`docs/architecture.md`](docs/architecture.md) for project structure and design decisions.

---

## Contributing

Tech packs and engine improvements welcome.

1. Fork
2. Create feature branch
3. Run `swift test`
4. Open PR

For building new packs, read [Creating Tech Packs](docs/creating-tech-packs.md).

---

## License

MIT

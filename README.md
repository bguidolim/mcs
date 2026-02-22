# mcs -- My Claude Setup

One command to turn Claude Code into a fully equipped development environment with persistent memory, automated workflows, and platform-specific tooling.

```bash
brew install bguidolim/tap/my-claude-setup
mcs install --all
```

That's it. Claude Code now has MCP servers for semantic search and documentation, plugins for PR reviews and iterative refinement, session hooks that load git context on startup, and a continuous learning system that remembers what it discovers across sessions.

## What Problem Does This Solve?

Claude Code is powerful out of the box, but getting the most from it requires configuring MCP servers, installing plugins, writing session hooks, managing settings, and maintaining per-project instruction files. Doing this manually is tedious, error-prone, and hard to keep consistent across machines and projects.

`mcs` automates all of it. It installs and configures everything in one pass, tracks what it installed, detects configuration drift, and auto-fixes issues. It is non-destructive by design: every file write creates a timestamped backup, you can preview changes with `--dry-run`, and the interactive installer lets you pick only the components you want.

## What You Get

**Persistent Memory** -- Learnings and architectural decisions are extracted from sessions into markdown files, indexed by a local embedding model (Ollama + nomic-embed-text), and searchable via the docs-mcp-server MCP. Claude Code remembers what it learned last week.

**Context-Aware Sessions** -- Every session starts with a hook that surfaces git status, branch protection rules, open PRs, and Ollama health. Claude Code knows where it is before you ask anything.

**Automated PR Workflows** -- The `/pr` slash command stages, commits, pushes, and creates a pull request in one step, extracting ticket numbers from branch names. The `/commit` command does the same without the PR. Plugins add specialized review agents for code quality, silent failures, and test coverage.

**Per-Project Configuration** -- `mcs configure` generates a `CLAUDE.local.md` file with instructions tuned to your project's technology stack, managed through section markers that separate tool-controlled content from your own notes.

**Self-Healing Setup** -- `mcs doctor` runs a multi-layer diagnostic across dependencies, MCP servers, plugins, hooks, settings, file freshness, and project state. Add `--fix` to auto-repair what it can.

**Tech Packs** -- Platform-specific tools are organized into installable packs. The iOS pack ships today with XcodeBuildMCP (build, test, run iOS/macOS apps), Sosumi (Apple documentation search), and simulator workflow guidance. The architecture supports additional packs for other platforms.

## Quick Start

### Prerequisites

- macOS (Apple Silicon or Intel)
- Xcode Command Line Tools: `xcode-select --install`
- Homebrew: [brew.sh](https://brew.sh)

### Install via Homebrew

```bash
brew install bguidolim/tap/my-claude-setup
```

### Run the installer

Install everything non-interactively:

```bash
mcs install --all
```

Or pick components interactively:

```bash
mcs install
```

### Configure your project

```bash
cd your-project
mcs configure
```

This generates `CLAUDE.local.md` with instructions for your project, creates pack-specific configuration files (like `.xcodebuildmcp/config.yaml` for iOS projects), and sets up the memory directory.

### Verify

```bash
mcs doctor
```

## Usage

### `mcs install`

Installs and configures Claude Code components.

```bash
mcs install                # Interactive -- pick components from a menu
mcs install --all          # Install everything without prompts
mcs install --dry-run      # Preview what would be installed (no changes)
mcs install --pack ios     # Install only iOS tech pack components
```

The installer runs in five phases: system checks, component selection, dependency resolution, installation, and post-install summary. Dependencies like Node.js, Ollama, and the GitHub CLI are auto-resolved based on your selections.

### `mcs doctor`

Diagnoses installation health across seven layers of checks.

```bash
mcs doctor                 # Check core + installed packs
mcs doctor --fix           # Check and auto-fix issues
mcs doctor --pack ios      # Only check the iOS pack
```

When run inside a project, doctor automatically detects which packs are configured and scopes its checks accordingly. It reads from the project's `.mcs-project` state file, falls back to inferring packs from `CLAUDE.local.md` section markers, and finally consults the global manifest.

### `mcs configure`

Generates per-project `CLAUDE.local.md` and pack-specific files.

```bash
mcs configure              # Interactive pack selection
mcs configure --pack ios   # Apply a specific pack
mcs configure /path/to/project  # Target a different directory
```

Running configure on an already-configured project updates managed sections to the current version while preserving any content you added outside the section markers.

### `mcs cleanup`

Finds and deletes backup files created by previous installs and configurations.

```bash
mcs cleanup                # Interactive -- lists backups, asks before deleting
mcs cleanup --force        # Delete without confirmation
```

## Components

### Core

| Category | Component | Description |
|----------|-----------|-------------|
| MCP Server | docs-mcp-server | Semantic search over project memories using local Ollama embeddings |
| MCP Server | Serena | Semantic code navigation, symbol editing, and project context via LSP |
| Plugin | explanatory-output-style | Enhanced output with educational insights |
| Plugin | pr-review-toolkit | Specialized PR review agents for code quality, silent failures, test coverage |
| Plugin | ralph-loop | Iterative refinement loop for complex multi-step tasks |
| Plugin | claude-md-management | Audit and improve CLAUDE.md files |
| Skill | continuous-learning | Extracts learnings and decisions from sessions into memory files |
| Command | /pr | Stages, commits, pushes, and creates a PR with ticket extraction |
| Command | /commit | Stages, commits, and pushes without PR creation |
| Hook | session_start | Surfaces git status, branch protection, open PRs, Ollama health |
| Hook | continuous-learning-activator | Reminds Claude to evaluate learnings after each prompt |
| Config | settings.json | Plan mode, always-thinking, environment variables, hooks, plugins |

### iOS Tech Pack

Installed with `mcs install --pack ios` or included in `mcs install --all`.

| Category | Component | Description |
|----------|-----------|-------------|
| MCP Server | XcodeBuildMCP | Build, test, and run iOS/macOS apps via Xcode integration |
| MCP Server | Sosumi | Search and fetch Apple Developer documentation |
| Skill | xcodebuildmcp | Tool catalog and workflow guidance for iOS development |
| Template | CLAUDE.local.md section | iOS-specific instructions for simulator and build workflows |
| Config | .xcodebuildmcp/config.yaml | Per-project XcodeBuildMCP configuration |

### Auto-Resolved Dependencies

Based on your selections, `mcs` automatically installs these if not already present:

- **Homebrew** -- macOS package manager
- **Node.js** -- for npx-based MCP servers and skills
- **GitHub CLI (gh)** -- for the /pr command
- **jq** -- JSON processor used by session hooks
- **Ollama** + nomic-embed-text -- local embeddings for docs-mcp-server
- **uv** -- Python package runner for the Serena MCP server
- **Claude Code** -- the Claude Code CLI itself

## Memory System

The continuous learning system stores knowledge as plain markdown files in `<project>/.claude/memories/`:

```
Session work
    |
    v
continuous-learning skill --> writes .claude/memories/*.md
    |
    v
session_start hook --> docs-mcp-server scrape --> Ollama embeddings
    |
    v
docs-mcp-server MCP --> search_docs --> semantic search results
```

Memory files follow naming conventions:

- `learning_<topic>_<detail>.md` -- non-obvious debugging insights, workarounds, gotchas
- `decision_<domain>_<topic>.md` -- architecture choices, conventions, rationale

These files are gitignored and local to your machine. If Serena is installed, `mcs configure` creates a `.serena/memories` symlink pointing to `.claude/memories` so both systems share the same knowledge base.

## Safety Guarantees

- **Backup on every write**: timestamped backups created before any file modification (`settings.json.backup.20260222_143000`)
- **Dry run**: `mcs install --dry-run` previews all changes without touching the filesystem
- **Interactive selection**: pick only the components you need, or use `--all` for everything
- **Idempotent**: re-run `mcs install` any time -- already-installed components are detected and skipped
- **Non-destructive settings merge**: existing `settings.json` entries are preserved; only new keys are added
- **Section markers**: `CLAUDE.local.md` uses HTML comment markers (`<!-- mcs:begin/end -->`) to separate managed content from your own
- **Manifest tracking**: SHA-256 hashes of installed files detect configuration drift

## Tech Pack System

Components are organized into tech packs. The core is technology-agnostic; platform-specific tools live in packs.

Currently shipped:
- **Core** -- memory, PR workflows, session hooks, plugins, Serena
- **iOS** -- XcodeBuildMCP, Sosumi, simulator management, Xcode integration

Packs are compiled into the single `mcs` binary -- no separate downloads or plugin registries. See [docs/creating-tech-packs.md](docs/creating-tech-packs.md) for how to create new packs.

## Troubleshooting

Run `mcs doctor` to diagnose issues. Common problems:

**Ollama not running**
```bash
ollama serve                       # Start in foreground
brew services start ollama         # Or start as background service
ollama pull nomic-embed-text       # Ensure embedding model is installed
```

**MCP servers not appearing in Claude Code**
```bash
claude mcp list                    # List registered servers
mcs doctor --fix                   # Auto-fix what can be fixed
mcs install                        # Re-run install for additive repairs
```

**CLAUDE.local.md out of date**
```bash
mcs configure                      # Regenerate with current templates
```

See [docs/troubleshooting.md](docs/troubleshooting.md) for a complete guide.

## Development

```bash
swift build                                              # Build debug
swift test                                               # Run tests
swift build -c release --arch arm64 --arch x86_64        # Universal release binary
```

See [docs/architecture.md](docs/architecture.md) for the project structure and design decisions.

## Contributing

Contributions are welcome, especially new tech packs. See [docs/creating-tech-packs.md](docs/creating-tech-packs.md) for a step-by-step guide to building a tech pack.

To contribute:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `swift test` to verify
5. Open a pull request

## License

MIT

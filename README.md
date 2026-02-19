# Claude Code iOS Development Setup

One command to turn [Claude Code](https://docs.anthropic.com/en/docs/claude-code) into a full-featured iOS development environment — MCP servers, plugins, skills, and hooks, all pre-configured.

### What you get

- 🔨 **Build, test, and run** iOS apps through Claude — no manual Xcode switching
- 📚 **Apple docs at your fingertips** — search Developer documentation inline while coding
- 🧠 **Semantic code intelligence** — navigate by symbol, edit structurally, persist learnings across sessions
- 🔍 **Automated PR reviews** — specialized agents for code quality, silent failures, and test coverage
- ⚡ **Context-aware sessions** — Claude starts every session knowing your git state, simulator, branch, and open PRs
- 📋 **Per-project templates** — auto-generate `CLAUDE.local.md` tuned to your Xcode workspace
- 🩺 **Self-healing setup** — built-in diagnostics that detect and auto-fix configuration drift

> **Safe to try**: preview with `--dry-run`, pick only the components you need, automatic backups before any file changes. Fully idempotent — re-run anytime.

## Quick Start

One-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/bguidolim/my-claude-ios-setup/main/install.sh | bash
```

Or clone manually:

```bash
git clone https://github.com/bguidolim/my-claude-ios-setup.git
cd my-claude-ios-setup
./setup.sh
```

The script is interactive — it will ask what you want to install before making any changes.

After install, the `claude-ios-setup` command is available globally — restart your terminal to pick up PATH changes.

### Prerequisites

- **macOS** (Apple Silicon or Intel)
- **Xcode** with Command Line Tools (`xcode-select --install`)
- **Anthropic account** with Claude Code access

## Usage

After installation, use the `claude-ios-setup` command from anywhere:

```bash
claude-ios-setup                   # Interactive setup (pick components)
claude-ios-setup --all             # Install everything (minimal prompts)
claude-ios-setup --dry-run         # Show what would be installed (no changes)
claude-ios-setup doctor            # Diagnose installation health
claude-ios-setup doctor --fix      # Diagnose and auto-fix issues
claude-ios-setup configure-project # Configure CLAUDE.local.md for a project
claude-ios-setup cleanup           # Find and delete backup files
claude-ios-setup update            # Pull latest version from GitHub
claude-ios-setup --help            # Show usage
```

Or if running from a local clone, use `./setup.sh` with the same arguments.

## What Gets Installed

The script lets you pick from the following components:

### MCP Servers

| Server | Description |
|--------|-------------|
| **XcodeBuildMCP** | Build, test, and run iOS/macOS apps via Xcode integration |
| **Sosumi** | Search and fetch Apple Developer documentation |
| **Serena** | Semantic code navigation, symbol editing, and persistent memory via LSP |
| **docs-mcp-server** | Semantic search over docs and memories using local Ollama embeddings |

### Plugins

| Plugin | Description |
|--------|-------------|
| **explanatory-output-style** | Enhanced output with educational insights |
| **pr-review-toolkit** | PR review agents (code-reviewer, silent-failure-hunter, etc.) |
| **ralph-loop** | Iterative refinement loop for complex tasks |
| **claude-hud** | Status line HUD with real-time session info |
| **claude-md-management** | Audit and improve CLAUDE.md files |

### Skills

| Skill | Description |
|-------|-------------|
| **continuous-learning** | Extracts learnings and decisions into Serena memory |
| **xcodebuildmcp** | Official skill with guidance for 190+ iOS dev tools |

### Commands

| Command | Description |
|---------|-------------|
| **/pr** | Automates stage → commit → push → PR creation with ticket extraction |

### Configuration

| Config | Description |
|--------|-------------|
| **Session hooks** | On startup: git context (branch, uncommitted changes, stash, conflicts, remote tracking, open PRs), simulator UUID, Ollama status, docs-mcp library sync. On each prompt: learning reminder |
| **Settings** | Plan mode by default, always-thinking, env vars, hooks config, plugins |

### Dependencies (auto-resolved)

The script automatically installs required dependencies based on your selections:

- **Homebrew** — if any packages need installing
- **Node.js** — for npx-based MCP servers and skills
- **jq** — for JSON config merging
- **gh** — GitHub CLI (when /pr command is selected)
- **uv** — for Serena (Python-based)
- **Ollama** + `nomic-embed-text` — for docs-mcp-server embeddings

## Post-Setup: Per-Project Configuration

After running the setup script, configure each iOS project:

### 1. Add CLAUDE.local.md

If you cloned the repo:

```bash
cd my-claude-ios-setup
./setup.sh configure-project
```

If you used the one-line installer, clone and run:

```bash
git clone https://github.com/bguidolim/my-claude-ios-setup.git
cd my-claude-ios-setup
./setup.sh configure-project
```

This auto-detects your Xcode project, asks for your name, generates `CLAUDE.local.md` with placeholders filled in, and creates `.xcodebuildmcp/config.yaml`.

### 2. Authenticate Claude Code

If this is a fresh install, run `claude` and follow the authentication prompts.

## Configuration Files

| File | Purpose |
|------|---------|
| `config/settings.json` | Claude Code settings (env vars, hooks, plugins, permissions) |
| `hooks/session_start.sh` | Session startup hook |
| `hooks/continuous-learning-activator.sh` | Learning reminder hook |
| `skills/continuous-learning/` | Custom continuous-learning skill |
| `commands/pr.md` | /pr custom command template |
| `templates/CLAUDE.local.md` | Per-project Claude instructions template |
| `templates/xcodebuildmcp.yaml` | XcodeBuildMCP per-project config template |

## Customization

### Adding More MCP Servers

```bash
# stdio server
claude mcp add my-server -- npx my-mcp-package

# HTTP server
claude mcp add --transport http my-server https://example.com/mcp

# With environment variables
claude mcp add -e API_KEY=xxx my-server -- npx my-mcp-package
```

### Adding More Plugins

```bash
# From official marketplace
claude plugin install plugin-name@claude-plugins-official

# From a custom marketplace
claude plugin marketplace add github-user/repo
claude plugin install plugin-name@repo
```

### Adding More Skills

```bash
# From the skills ecosystem
npx skills add github-user/skill-repo
```

## Troubleshooting

### Ollama not starting
```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Start Ollama (Homebrew install)
brew services start ollama

# Start Ollama (manual install)
ollama serve
```

### MCP servers not appearing
```bash
# List configured servers
claude mcp list

# Re-add a server
claude mcp remove my-server
claude mcp add my-server -- npx my-mcp-package
```

### Plugin installation fails
```bash
# List available plugins
claude plugin list

# Update marketplace
claude plugin marketplace update
```

### npx skills not found
```bash
# Ensure Node.js is installed
node --version
npx --version

# Clear npx cache if needed
rm -rf ~/.npm/_npx
```

### Serena language server issues
```bash
# Verify SourceKit-LSP is available
xcrun sourcekit-lsp --help

# Check Serena dashboard
# Open http://127.0.0.1:24282/dashboard/ in your browser
```

## Backups

The script creates timestamped backups before modifying existing files:
- `~/.claude/settings.json.backup.YYYYMMDD_HHMMSS`
- `~/.claude.json.backup.YYYYMMDD_HHMMSS`
- `<project>/CLAUDE.local.md.backup.YYYYMMDD_HHMMSS` (when `configure-project` overwrites)

## License

MIT

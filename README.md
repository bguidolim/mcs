# My Claude Setup (`mcs`)

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)]()
[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)]()
[![Homebrew Tap](https://img.shields.io/badge/homebrew-tap-yellow.svg)]()

> [!WARNING]
> **This project is under active development.** Expect breaking changes, bugs, and incomplete features. Migrations between versions are not guaranteed. Use at your own risk.

## Reproducible AI infrastructure for Claude Code.

`mcs` installs and manages MCP servers, semantic memory, PR automation agents, session hooks, and stack-specific tooling — turning Claude Code into a persistent, context-aware AI development environment.

**Built for developers who want:**

- Semantic project memory (local embeddings via Ollama)
- Automated PR reviews and commit workflows
- LSP-aware code navigation (Serena)
- Reproducible setup across machines
- Drift detection and self-healing configuration

```bash
brew install bguidolim/tap/my-claude-setup && mcs install --all
```

---

# What Is `mcs`?

`mcs` (My Claude Setup) is a structured installer and configuration manager for Claude Code on macOS.

It automates what experienced developers end up building manually:

- MCP server installation
- Memory wiring with embeddings
- PR review agents
- Session lifecycle hooks
- Managed `settings.json`
- Stack-aware project configuration
- Drift detection and repair
- Platform toolchains via Tech Packs

Instead of maintaining fragile scripts and dotfiles, you get:

**Reproducible. Idempotent. Portable.**

---

# Why Use `mcs`?

| | Capability | Why it matters |
|---|------------|---------------|
| 🧠 | **Persistent Memory** | Claude retains decisions and learns across sessions via semantic search |
| 🔍 | **Automated PR Reviews** | Catch silent failures, regressions, and coverage gaps automatically |
| ⚡ | **Context-Aware Sessions** | Every session starts with git state, branch protection, PRs, system health |
| 🛠️ | **Per-Project Intelligence** | Auto-generated `CLAUDE.local.md` tuned to your stack |
| 🩺 | **Self-Healing Setup** | `mcs doctor --fix` repairs configuration drift |
| 📦 | **Tech Packs** | Install platform-specific tooling (iOS pack available) |
| 🌍 | **Portable by Design** | Recreate your entire Claude environment in minutes |

---

# Manual Setup vs `mcs`

| Manual Claude Setup | With `mcs` |
|---------------------|------------|
| Install MCP servers individually | Single command install |
| Hand-edit `settings.json` | Managed, non-destructive configuration |
| Manually wire hooks | Auto-installed session hooks |
| No memory persistence | Semantic memory with embeddings |
| PR workflow via custom scripts | Built-in `/pr` and review agents |
| Configuration drifts over time | SHA-based drift detection |
| Rebuild from memory on new machine | Fully reproducible in minutes |

**Stop configuring Claude manually. Start versioning your AI environment.**

---

# Portable & Reproducible

Your Claude environment becomes infrastructure.

`mcs` tracks:

- Installed components
- Dependency state
- Configuration hashes (SHA-256)
- Managed file sections

You can:

- Set up a new Mac quickly
- Keep multiple machines aligned
- Re-run safely at any time
- Detect and repair drift automatically
- Avoid dotfile sprawl

Re-run it today. Re-run it in six months. It still works.

---

# Quick Start

```bash
brew install bguidolim/tap/my-claude-setup
mcs install --all
cd your-project && mcs configure
mcs doctor
```

---

<details>
<summary><strong>Prerequisites</strong></summary>

- macOS (Apple Silicon or Intel)
- Xcode Command Line Tools  
  ```bash
  xcode-select --install
  ```
- Homebrew

</details>

---

# How It Works

`mcs` acts as a declarative configuration layer for Claude Code.

```
mcs install          → install components + resolve dependencies + record state
mcs configure        → generate per-project CLAUDE.local.md
mcs doctor [--fix]   → 7-layer diagnostic + auto-repair
mcs cleanup          → remove stale backups
```

Every change is:

- Backed up
- Section-delimited
- Idempotent
- Manifest-tracked

Architecture details: see [`docs/architecture.md`](docs/architecture.md)

---

# Core Components

| | Component | Purpose |
|---|-----------|----------|
| 🔌 | **docs-mcp-server** | Semantic memory search (local Ollama embeddings) |
| 🔌 | **Serena** | Symbol-aware code navigation and editing via LSP |
| 🧩 | **pr-review-toolkit** | Structured AI PR review agents |
| 🧩 | **ralph-loop** | Iterative refinement loop for complex tasks |
| 🧩 | **explanatory-output-style** | Enhanced output with reasoning context |
| 🧩 | **claude-md-management** | Audit and improve `CLAUDE.md` |
| 📋 | **continuous-learning** | Automatically extract learnings into memory |
| 📋 | **/pr & /commit** | Stage, commit, push, optionally open PR |
| ⚙️ | **session_start hook** | Git status, PRs, Ollama health at session start |
| ⚙️ | **Managed settings.json** | Plan mode, always-thinking, plugins, hooks |

---

# Memory System

Claude becomes progressively smarter about your project.

```
Session work
   ↓
continuous-learning skill
   ↓
.claude/memories/*.md
   ↓
docs-mcp-server + Ollama embeddings
   ↓
semantic retrieval in future sessions
```

- Plain Markdown files
- Local-only
- Gitignored
- Shared with Serena when installed
- No external cloud required

---

# Tech Packs

Tech Packs group platform-specific tooling into modular bundles compiled into the `mcs` binary.

| Pack | Includes |
|------|----------|
| **Core** | Memory, PR workflows, session hooks, Serena |
| **iOS** | XcodeBuildMCP, Sosumi, simulator + Xcode workflows |

Want to create your own pack?  
See [`docs/creating-tech-packs.md`](docs/creating-tech-packs.md).

---

# iOS Tech Pack

Install with:

```bash
mcs install --pack ios
```

Includes:

| | Component | Purpose |
|---|-----------|----------|
| 🔌 | **XcodeBuildMCP** | Build, test, run apps via Xcode |
| 🔌 | **Sosumi** | Search Apple Developer documentation |
| 📋 | **xcodebuildmcp skill** | Guided workflows for 190+ iOS tools |
| ⚙️ | **iOS CLAUDE.local.md section** | Simulator + build workflow tuning |
| ⚙️ | **xcodebuildmcp.yaml** | Per-project configuration |

---

# Auto-Resolved Dependencies

Installed automatically when required:

- Node.js (npx-based MCP servers)
- GitHub CLI (`gh`) for `/pr`
- `jq` for hook JSON parsing
- Ollama + `nomic-embed-text` for local embeddings
- `uv` for Serena
- Claude Code CLI

---

# Safety Guarantees

| Guarantee | Meaning |
|-----------|--------|
| 🔒 Backups | Timestamped backup before every write |
| 👁️ Dry Run | `--dry-run` previews changes |
| 🎯 Selective Install | Choose components or use `--all` |
| 🔄 Idempotent | Safe to re-run anytime |
| 🧩 Non-Destructive | Existing configuration preserved |
| 📐 Section Markers | Managed content clearly separated |
| 🔎 Drift Detection | SHA-based manifest tracking |

---

# Troubleshooting

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

# Development

```bash
swift build
swift test
swift build -c release --arch arm64 --arch x86_64
```

See [`docs/architecture.md`](docs/architecture.md) for project structure and design decisions.

---

# Contributing

Tech Packs and improvements welcome.

1. Fork
2. Create feature branch
3. Run `swift test`
4. Open PR

For building new packs, read [`docs/creating-tech-packs.md`](docs/creating-tech-packs.md)

---

# License

MIT

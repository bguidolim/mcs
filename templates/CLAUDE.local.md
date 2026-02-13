# Claude Code Instructions

<!-- EDIT: If your project has CLAUDE.md as a symlink to AGENTS.md, uncomment the note below -->
<!-- > **Note:** `CLAUDE.md` is a symlink to `AGENTS.md` — its content is already loaded at session start. Do not re-read `AGENTS.md` or `CLAUDE.md` via tool calls. -->

## Knowledge Base (MANDATORY — Query First)

### Exploration & Discovery
When exploring the codebase for a new task — especially during plan mode — **ALWAYS search the KB first** before using other discovery tools (Serena, Grep, Glob, etc.):

1. **Search `search_docs`** with keywords relevant to the task (module name, feature, pattern, or concept). It indexes **both documentation and Serena memories** in a single semantic search, so it is the preferred entry point.
2. **Read the files** referenced in the search results (source files, docs, or memories) — the KB may already provide the architecture, decisions, and relevant file paths you need.
3. **Then continue** exploring with Serena, Glob, or other tools only for what the KB didn't cover.

### Search Tips
- The `library` parameter is typically the **folder/project name** (e.g., the module or repo you're working in)
- Use multiple keyword variations if the first search returns few results (e.g., "phone call" and "VoIP")
- If `search_docs` returns no results or is unavailable, fall back to `list_libraries` to discover available libraries, then retry
- **Re-search** when switching context to a different module or feature area
- Serena `list_memories` can also be used, but prefer `search_docs` first since it provides semantic search across both docs and memories

### Serena Memory (Writing)
- **Writing** (always use Serena): Save to memory any architectural decisions, gotchas, patterns, or context useful across sessions
- **Keep memory in sync** — update existing memories when findings evolve rather than creating duplicates

## Serena MCP (MANDATORY)

### Code Discovery & Navigation

You **MUST** use Serena for Swift code discovery, navigation, and editing:
- Use `get_symbols_overview` to understand file structure before editing
- Use `find_symbol` with `include_body=True` to read specific symbol implementations
- Use `find_referencing_symbols` to understand symbol usage and impact of changes
- Use `search_for_pattern` instead of Grep for code searches
- **Before removing or renaming any symbol**, verify it is truly unused by checking all references with `find_referencing_symbols` or `search_for_pattern`

### Code Editing
- Use `replace_symbol_body` for modifying existing symbol implementations
- Use `insert_before_symbol` / `insert_after_symbol` for adding new code
- **NEVER** use Read/Edit/Grep tools for Swift files when Serena equivalents exist

### Available Serena Tools
| Category | Tools |
|----------|-------|
| **Discovery** | `get_symbols_overview`, `find_symbol`, `find_referencing_symbols`, `search_for_pattern` |
| **Editing** | `replace_symbol_body`, `insert_before_symbol`, `insert_after_symbol` |
| **Memory** | `list_memories`, `read_memory`, `write_memory`, `edit_memory` |

## iOS Simulator
- Always use the **booted simulator first**
- Always reference simulators by **UUID**, not by name
- If no simulator is booted, **ask the user** which one to use

## Build & Test (XcodeBuildMCP)

All build, test, and run operations go through **XcodeBuildMCP** (see the `xcodebuildmcp` skill for the full tool catalog).

XcodeBuildMCP has two tool families: **`xcode_tools_*`** (Xcode IDE, incremental builds — fast) and **CLI tools** (`build_sim`, `test_sim`, etc. — full `xcodebuild` builds, slower). Default to `xcode_tools_*` unless you need scheme switching, `-only-testing`, or UI interaction.

### Rules
- Before the first build/test in a session, call `session_show_defaults` to verify the active project, scheme, and simulator
- **Never** run `xcrun` or `xcodebuild` directly via Bash — always use XcodeBuildMCP tools
- **Never** build or test unless explicitly asked
<!-- EDIT: Set your .xcodeproj and default scheme below -->
- Always use `__PROJECT__.xcodeproj` with the appropriate scheme
- **Never** suppress warnings — if any are related to the session, fix them
- Prefer `snapshot_ui` over `screenshot` (screenshot only as fallback)

## Code Reviews
- When asked to **review a PR** or **answer a question about code**, do NOT make code edits or run commands unless explicitly asked
- Review tasks are **read-only by default** — provide findings in conversation only
- Do not post GitHub comments unless explicitly asked

## Git & GitHub
<!-- EDIT: Set your branch naming convention below -->
- Branch naming: `<your-name>/{ticket-and-small-title}`
- **Never commit without being asked**
- Use `gh` command for GitHub queries (auth already configured)

### Commit Message
- One-line short description
- Max 3 bullet points
- Consider only the actual changes being committed

## Knowledge Management
When learning something new about the codebase:
- **Suggest updates** to `AGENTS.md` (project-level) or `CLAUDE.md` (module-level)
- **Never modify** these files proactively — only suggest changes

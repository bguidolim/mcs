---
name: continuous-learning
description: |
  Continuous learning system that monitors all user requests and interactions to identify
  learning opportunities and project decisions. Active during: (1) Every user request and task,
  (2) All coding sessions and problem-solving activities, (3) When discovering solutions, patterns,
  or techniques, (4) When making architectural or design decisions, (5) When establishing best
  practices or preferences, (6) During /retrospective sessions. Automatically evaluates whether
  current work contains valuable knowledge or decisions and saves memories via Serena MCP.
allowed-tools:
  - mcp__serena__write_memory
  - mcp__serena__read_memory
  - mcp__serena__list_memories
  - mcp__serena__delete_memory
  - mcp__serena__edit_memory
  - mcp__serena__find_symbol
  - mcp__serena__read_file
  - mcp__serena__search_for_pattern
  - mcp__serena__get_symbols_overview
  - mcp__docs-mcp-server__search_docs
  - mcp__docs-mcp-server__list_libraries
  - mcp__mcp-omnisearch__ai_search
  - mcp__sosumi__searchAppleDocumentation
  - mcp__sosumi__fetchAppleDocumentation
  - AskUserQuestion
  - TodoWrite
---

# Continuous Learning Skill

Extract reusable knowledge from work sessions and save it as memories via Serena MCP.

## Memory Categories

### Learnings (`learning_<topic>_<specific>`)

Knowledge discovered through debugging, investigation, or problem-solving that wasn't obvious beforehand.

**Extract when:**
- Solution required significant investigation (not a documentation lookup)
- Error message was misleading — root cause was non-obvious
- Discovered a workaround for a tool/framework limitation
- Found a workflow optimization through experimentation

**Examples:** `learning_swiftui_task_cancellation`, `learning_xcode_build_cache_corruption`, `learning_combine_nested_sink_retain_cycle`

### Decisions (`decision_<domain>_<topic>`)

Deliberate choices about how the project should work.

**Extract when:**
- Architectural choice made (patterns, structures, dependencies)
- Convention or style preference established
- Tool/library selected over alternatives with reasoning
- User says "let's use X", "I prefer Y", "from now on..."
- Trade-off resolved between competing concerns

**Domain prefixes:**

| Domain | Examples |
|--------|----------|
| `architecture` | `decision_architecture_mvvm_coordinator` |
| `codestyle` | `decision_codestyle_explicit_self` |
| `tooling` | `decision_tooling_swiftlint_rules` |
| `testing` | `decision_testing_snapshot_strategy` |
| `networking` | `decision_networking_async_await` |
| `ui` | `decision_ui_color_system` |
| `assets` | `decision_assets_pdf_format` |
| `project` | `decision_project_minimum_ios_version` |

---

## Extraction Workflow

### Step 1: Evaluate the Current Task

After completing any task, ask:
- Did this require non-obvious investigation or debugging?
- Was a choice made about architecture, patterns, or approach?
- Did the user express a preference or convention?
- Would future sessions benefit from having this documented?

If NO to all → skip. If YES to any → continue.

### Step 2: Search Existing Knowledge

**Always search docs-mcp-server first** (semantic search across documentation and Serena memories):

```
mcp__docs-mcp-server__search_docs(library: "<project>", query: "<topic>")
```

**Fall back to Serena** if search_docs returns no results:

```
mcp__serena__list_memories()
```

Determine if: update an existing memory, cross-reference related memories, or knowledge is already captured.

### Step 3: Research (When Appropriate)

**For Apple/iOS/Swift topics** — use Sosumi first:
```
mcp__sosumi__searchAppleDocumentation(query: "<topic>")
```

**For general topics** — use OmniSearch:
```
mcp__mcp-omnisearch__ai_search(query: "<topic> best practices 2026", provider: "perplexity")
```

**Skip research for:** project-specific conventions, personal preferences, time-sensitive captures.

### Step 4: Structure and Save

Read [references/templates.md](references/templates.md) for the full template structures.

**For learnings:** Use the Learning Memory Template (Problem → Trigger Conditions → Solution → Verification → Example → Notes → References).

**For decisions:** Use the ADR-Inspired Template for complex trade-offs, or the Simplified Template for straightforward preferences.

**Save:**
```
mcp__serena__write_memory(name: "<category>_<topic>_<specific>", content: "<structured markdown>")
```

**Update existing:**
```
mcp__serena__edit_memory(name: "<existing_name>", content: "<updated markdown>")
```

---

## Quality Gates

Before saving any memory, verify:
- [ ] Name follows the correct pattern (`learning_` or `decision_<domain>_`)
- [ ] Content uses the appropriate template from references/templates.md
- [ ] Solution is verified to work (not theoretical)
- [ ] Content is specific enough to be actionable
- [ ] Content is general enough to be reusable
- [ ] No sensitive information (credentials, internal URLs)
- [ ] Does not duplicate existing memories
- [ ] References included if external sources were consulted

---

## Retrospective Mode

When `/retrospective` is invoked:

1. Review conversation history for extractable knowledge
2. Search existing memories via `search_docs` then `list_memories`
3. List candidates with brief justifications
4. Extract top 1-3 highest-value memories
5. Report what was created and why

---

## Tool Reference

| Tool | Purpose |
|------|---------|
| `mcp__docs-mcp-server__search_docs` | **Primary:** Semantic search across docs and memories |
| `mcp__docs-mcp-server__list_libraries` | List indexed libraries |
| `mcp__serena__list_memories` | **Fallback:** List all memories |
| `mcp__serena__read_memory` | Read a specific memory |
| `mcp__serena__write_memory` | Create new memory |
| `mcp__serena__edit_memory` | Update existing memory |
| `mcp__serena__delete_memory` | Remove outdated memory |
| `mcp__sosumi__searchAppleDocumentation` | Search Apple Developer docs |
| `mcp__sosumi__fetchAppleDocumentation` | Fetch specific Apple doc by path |
| `mcp__mcp-omnisearch__ai_search` | AI-powered web search (perplexity/kagi/exa) |

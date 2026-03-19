---
description: "Hooker main hub — browse recipes, create hooks, show status"
args: "[recipe-name | natural language description | list|install|remove|installed]"
---

# Hooker

Universal hook injection framework for Claude Code. This is the main entry point.

## Hook file locations (priority order)

1. **Project-level**: `.claude/hooker/` — overrides everything, version-controllable
2. **User-global**: `~/.claude/hooker/` — applies to all projects unless overridden
3. **Plugin defaults**: `${CLAUDE_PLUGIN_ROOT}/templates/` — ships with plugin

When creating, editing, or troubleshooting hooks — check all three locations.

## With natural language description
If the user describes what they want (e.g. `/hooker:recipe block deploys on fridays`, `/hooker:recipe remind about docs`):
1. Figure out which hook event(s) are needed
2. Check if an existing recipe covers this — if so, offer to install it
3. Otherwise, decide the best mode (static template, conditional, or dynamic match script)
4. Create the files in `.claude/hooker/`
5. Test it

## Recipe catalog

Available recipes (no need to scan filesystem — this is the full list):

| Recipe | Hook | Description |
|--------|------|-------------|
| `agent-gets-claude-context` | SubagentStart | Injects CLAUDE.md and MEMORY.md into every subagent so they share the main session's project instructions and memory. |
| `auto-checkpoint` | Stop | Creates a git checkpoint commit when Claude stops responding. Easy rollback of changes. |
| `auto-format` | PostToolUse | Runs the appropriate formatter (prettier, ruff, gofmt, etc.) after every file edit. |
| `behavior-watchdog` | UserPromptSubmit | Periodically and on frustration signals, silently reminds Claude to check if its behavior is causing issues and suggests /hooker:recipe as a fix. |
| `block-dangerous-commands` | PreToolUse | Blocks rm -rf, fork bombs, curl|sh, DROP TABLE, and other destructive bash commands. |
| `compact-context` | PreCompact | Injects custom instructions into the compaction prompt. Lightweight alternative to the kompakt plugin — edit PreCompact.md to customize what the compactor preserves. |
| `detect-lazy-code` | PostToolUse | Catches when Claude replaces code with comments like '// ... rest of implementation' or leaves vague TODO/FIXME placeholders. |
| `git-context-on-start` | SessionStart | Injects current git branch, status, and recent commits on session start. |
| `no-force-push-main` | PreToolUse | Blocks git push --force to main/master branches. |
| `protect-sensitive-files` | PreToolUse | Blocks reading or editing .env, SSH keys, credentials, and other sensitive files. |
| `refactor-move-go-simple` | PostToolUse, PostCompact, SessionStart | After mv of .go files, updates import paths across the project. Reads go.mod for module path. Pure bash/sed — no external dependencies (gorename not required). |
| `refactor-move-python-simple` | PostToolUse, PostCompact, SessionStart | After mv of .py files, updates import statements (from X import Y, import X) across the project. Pure bash/sed — no external dependencies. Best adapted as a project-specific hook. |
| `refactor-move-ts-simple` | PostToolUse, PostCompact, SessionStart | After mv of .ts/.tsx/.js/.jsx files, updates import/require paths across the project. Reads tsconfig.json for baseUrl/path aliases. Requires python3 for reliable relative path computation (falls back to simpler approach without it). Best adapted as a project-specific hook. |
| `refactor-move-ts-smart` | PostToolUse, PostCompact, SessionStart | After mv of .ts/.tsx/.js/.jsx files, uses TypeScript Language Service API (getEditsForFileRename — same as VS Code) for AST-aware import rewriting. Handles path aliases, re-exports, barrel files. Requires typescript (global or local). Falls back to sed. |
| `reinject-after-compact` | SessionStart | Re-injects critical project context (from .claude/hooker/context.md) after compaction to prevent context loss. |
| `remind-to-update-docs` | Stop | Context-aware reminder on stop — checks what was edited (code/docs/tests) and shows appropriate message from messages.yml. Only fires if Edit/Write/NotebookEdit was used in the last turn. |
| `require-changelog-before-tag` | PreToolUse | Blocks git tag and push --tags unless CHANGELOG.md was updated in the current commit or staging area. |
| `session-guardian` | PostToolUseFailure, TaskCompleted, PostCompact, SessionEnd, SubagentStop | Lifecycle reminders: verify failed tools, check tests before task completion, re-inject context after compaction, remind to commit on session end, review subagent output. |
| `skip-acknowledgments` | UserPromptSubmit | Stops Claude from opening with 'Great question!', 'You're right!', etc. Focus on the solution. |
| `smart-session-notes` | PreCompact | Creates filtered markdown session notes before compaction. Configurable: include/exclude user messages, assistant text, errors, tool calls. Saves to .claude/hooker/session-notes.md. |

**Hooks without recipes**: PermissionRequest, Notification, TeammateIdle, InstructionsLoaded, ConfigChange, WorktreeCreate, WorktreeRemove, Elicitation, ElicitationResult

## Without arguments
1. Check `.claude/hooker/` to detect which recipes are already installed:
   - **Isolated mode**: check for subdirectories in `.claude/hooker/*/`
   - **Merged mode**: grep for `# @recipe` markers in `.claude/hooker/*.sh`
2. Show the catalog with [installed] / [ready] status
3. Ask user which recipe(s) to install

## Installation modes

When the user requests recipe installation, **always ask which mode they prefer** and explain the tradeoffs:

### Merged mode (stable, default)

Traditional approach. All recipes sharing the same hook are merged into one script.

**How it works:**
- Files go directly in `.claude/hooker/{HookName}.match.sh`
- Multiple recipes for the same hook → merged into one script with `@recipe` markers
- Hooker's `inject.sh` (registered in the plugin's hooks.json) dispatches to them

**Pros:** Relies only on the plugin's hooks.json. Stable, no workarounds.
**Cons:** Merging recipes is complex. One `.match.sh` per hook — can't have independent behaviors.

**Structure:**
```
.claude/hooker/
  Stop.match.sh                              ← merged script with @recipe markers
  remind-to-update-docs.messages.yml         ← recipe's editable messages
  auto-checkpoint.messages.yml               ← another recipe's messages
```

### Isolated mode (experimental)

Each recipe gets its own subdirectory. No merging needed.

**How it works:**
- Files go in `.claude/hooker/{recipe-name}/`
- A `run.sh` bridge script is created in `.claude/hooker/`
- Hook entries are added to `.claude/settings.json` pointing to `run.sh`
- Each recipe = separate hook command, Claude Code orchestrates independently

**Pros:** Clean separation. No merging. Each recipe can use `.md` templates independently.
**Cons:** `run.sh` finds the hooker plugin by scanning known cache paths
(`~/.claude/plugins/cache/hooker-marketplace/hooker/`) and calling its `inject.sh`.
This internal path structure is **not guaranteed by Anthropic** and may change between
Claude Code versions. If the plugin cache layout changes, `run.sh` must be updated.

**Structure:**
```
.claude/hooker/
  run.sh                                     ← bridge (finds hooker, delegates to inject.sh)
  refactor-move-ts-smart/
    PostToolUse.match.sh
    PostCompact.md
    SessionStart.md
    update-imports.cjs
    messages.yml
  auto-format/
    PostToolUse.match.sh
    messages.yml
```

**settings.json entries:**
```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "", "hooks": [{ "type": "command", "command": ".claude/hooker/run.sh .claude/hooker/refactor-move-ts-smart/PostToolUse" }] },
      { "matcher": "", "hooks": [{ "type": "command", "command": ".claude/hooker/run.sh .claude/hooker/auto-format/PostToolUse" }] }
    ]
  }
}
```

### Decision guide (present to user)

| | Merged (stable) | Isolated (experimental) |
|---|---|---|
| Multiple recipes, same hook | Merged into one script | Each runs independently |
| `.md` templates | Only one per hook (must inline in merged script) | Each recipe keeps its own |
| Supporting files | Prefixed: `{recipe}.messages.yml` | In subdirectory: `{recipe}/messages.yml` |
| Dependency | Plugin hooks.json only | Plugin hooks.json + settings.json + `run.sh` cache path lookup |
| Stability | Proven, stable | **Experimental** — `run.sh` depends on plugin cache path structure |
| Removal | Delete `@recipe` section from merged script | Delete subdirectory + settings.json entry |

**Recommendation:** Use merged mode for stability. Use isolated mode only if you need multiple
independent behaviors on the same hook and understand the risk.

## With recipe name (e.g. `/hooker:recipe remind-to-update-docs`)

### Merged mode installation
1. Read `${CLAUDE_PLUGIN_ROOT}/recipes/{name}/recipe.json` and the recipe's files
2. Show description and hooks
3. Check if `.claude/hooker/{HookName}.match.sh` already exists
4. **If no conflict:** use the recipe script as reference, adapt it to the project if needed, write to `.claude/hooker/`
5. **If conflict (same hook already has a script):** read the existing script, **merge both behaviors into one combined script** that runs both checks
6. **Wrap each recipe's logic in `@recipe` markers** (see below)
7. `chmod +x` any `.match.sh` files
8. Confirm installation

### Isolated mode installation
1. Read `${CLAUDE_PLUGIN_ROOT}/recipes/{name}/recipe.json` and the recipe's files
2. Show description and hooks
3. Create `.claude/hooker/{recipe-name}/` directory
4. Copy/adapt recipe files into the subdirectory
5. Ensure `.claude/hooker/run.sh` exists (create from `${CLAUDE_PLUGIN_ROOT}/scripts/run.sh` if not)
6. Create/update `.claude/hooker/hooker.env` — cache dir without version so `run.sh` auto-picks
   latest after plugin updates:
   ```bash
   # Hooker plugin cache dir (run.sh picks latest version automatically)
   HOOKER_CACHE_DIR="${HOME}/.claude/plugins/cache/hooker-marketplace/hooker"
   ```
   This survives plugin updates — `run.sh` always picks the latest version from this dir.
7. `chmod +x run.sh` and any `.match.sh` files
8. Add hook entries to `.claude/settings.json` for each hook in the recipe:
   ```json
   { "matcher": "", "hooks": [{ "type": "command", "command": ".claude/hooker/run.sh .claude/hooker/{recipe-name}/{HookName}" }] }
   ```
9. **Warn the user:** "Isolated mode uses `hooker.env` to find the plugin. After a plugin
   update, the path in `hooker.env` may point to an old cached version — re-run
   `/hooker:recipe install` or edit `.claude/hooker/hooker.env` to refresh it. The fallback
   auto-detection picks the latest version from cache, but this relies on a cache path
   structure not guaranteed by Anthropic."
10. Confirm installation

## Recipe markers (merged mode only)
Every recipe's logic MUST be wrapped in marker comments for traceability:
```bash
# @recipe remind-to-update-docs
...recipe logic here...
# @end-recipe remind-to-update-docs
```

This enables:
- `installed` subcommand: grep for `# @recipe` in `.claude/hooker/*.sh` to list what's installed
- `remove` subcommand: find and delete only the marked section, keep the rest
- User inspection: easy to see which recipes contributed to a merged script

**Always add markers** — even for single-recipe scripts (future merges depend on them).

## Subcommands
- `list` — show all available recipes (same as no args)
- `install <name> [name2...]` — install one or more recipes (asks which mode)
- `remove <name>` — **merged:** find `# @recipe <name>` / `# @end-recipe <name>` markers in `.claude/hooker/`, remove only that section. If it was the last recipe in the file, remove the file. **isolated:** delete `.claude/hooker/{name}/` directory and remove corresponding entries from `.claude/settings.json`.
- `installed` — detect installed recipes from both modes:
  - **Merged:** grep for `# @recipe <name>` in `.claude/hooker/*.sh`
  - **Isolated:** list subdirectories in `.claude/hooker/*/` that contain hook files

## IMPORTANT: recipes are REFERENCES, not copy-paste
Recipe scripts in `${CLAUDE_PLUGIN_ROOT}/recipes/` are templates to learn from.
When installing:
- **Read** the recipe script to understand the logic
- **Adapt** paths, patterns, messages to the current project
- **Merged mode:** merge with existing scripts if the same hook is already in use, wrap in `@recipe` markers
- **Isolated mode:** copy into subdirectory, add settings.json hooks
- **Never blindly copy** — the script may need project-specific adjustments

## Merge strategy for different modes (merged mode only)

Some recipes are Mode 2 (match script + `.md` template) or Mode 1 (`.md` only).
When merging, **always convert to Mode 3** (standalone script with output):

- If a recipe has a `.md` template, inline its content into the script's output
  (e.g. use `inject "..."` or `block "..."` instead of relying on the `.md` file)
- If a recipe's match script exits 0 without output (relying on `.md`), rewrite it
  to produce the output directly
- After merge, there should be **no `.md` template** — the combined script handles everything

This is necessary because:
- There can only be one `.md` file per hook — merging two `.md` files is ambiguous
- Mode 3 is the only mode that scales to multiple behaviors in one hook
- The combined script can decide which recipe's behavior to apply based on context

## Supporting files (messages.yml, config, etc.)

**Merged mode:** prefix with recipe name to prevent conflicts:
```
.claude/hooker/
  Stop.match.sh                              ← merged script with @recipe markers
  remind-to-update-docs.messages.yml         ← this recipe's editable messages
  auto-checkpoint.messages.yml               ← another recipe's config
```
Convention: `{recipe-name}.{original-filename}` — prevents conflicts between recipes.

**Isolated mode:** files stay in their recipe subdirectory — no prefixing needed:
```
.claude/hooker/
  remind-to-update-docs/
    Stop.match.sh
    messages.yml
  auto-checkpoint/
    Stop.match.sh
    messages.yml
```

## Architecture — THREE modes of operation

### Mode 1: Template only (`.md`, no `.match.sh`)
Static rule — always fires, content from template.
```
.claude/hooker/SessionStart.md  → always injects content on session start
```

### Mode 2: Template + match script (`.md` + `.match.sh` without output)
Conditional rule — match script decides IF, template decides WHAT.
```
.claude/hooker/Stop.md          → content to show
.claude/hooker/Stop.match.sh    → exit 0 if files were edited, else exit 1
```

### Mode 3: Standalone match script (`.match.sh` with output, no `.md` needed)
Full dynamic control — script decides everything. Uses helpers for output.
**This is the most powerful mode.** The script can read files, check state, build messages dynamically.
```
.claude/hooker/SubagentStart.match.sh  → reads CLAUDE.md, injects it
```

## Helpers library

Match scripts can `source "${HOOKER_HELPERS}"` to get pre-built functions:

**JSON responses (always visible to user):**
| Helper | Effect |
|--------|--------|
| `warn "msg"` | Warning, doesn't block |
| `deny "msg"` | Denies tool use (PreToolUse) |
| `allow "msg"` | Auto-allows tool use |
| `ask "msg"` | Escalates to user for decision |
| `block "msg"` | Blocks action (stop/prompt) |
| `remind "msg"` | Blocks stop with reminder |

**Context injection (hidden from user, only Claude sees):**
| Helper | Effect |
|--------|--------|
| `inject "text"` | Injects text into Claude's context (XML trick) |
| `context "text"` | Adds as additionalContext JSON |
| `visible "text"` | Outputs text visible to user |
| `load_md "file.md"` | Loads file content — only useful inside `inject()` |

**Visibility rules:**
- `inject()` is the **only** helper that hides content from user (via XML trick)
- All JSON helpers (warn, deny, block, remind, etc.) are **always fully visible** — Claude Code renders JSON reason/message as plaintext, XML trick cannot escape JSON strings
- `<visible>...</visible>` tags — inside inject templates (.md): shown to user
- `<hidden>` tags in JSON helpers are **stripped** (content discarded, not hidden)

**User-editable messages (recommended pattern):**
- Keep user-facing text in a `messages.yml` file alongside the match script, not hardcoded in bash
- Match script reads messages via `yml_get` helper using portable `sed`
- User can customize messages without touching script logic
- Script provides fallback defaults if yml is missing
- Project-level `.claude/hooker/messages.yml` overrides recipe default

Example `messages.yml`:
```yaml
code_changed: "You edited code — did you update docs and tests?"
docs_changed: "Are your docs complete and up to date?"
default: "Did you update docs, tests, and clean up TODOs?"
```

**Cross-platform rules (MUST follow when writing scripts):**
Scripts must work on Linux, macOS, and Windows (Git Bash). Rules:
- **NO** `grep -P` or `grep -oP` (PCRE) — use `sed -n 's/.../p'` for extraction, `grep -q` with POSIX patterns for matching
- **NO** `tac` — use `awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}'`
- **NO** `python3` or `perl` — use `awk` and `sed` for text processing
- **NO** `\s` in patterns — use `[[:space:]]`
- **NO** `\b` in patterns — use explicit context or `[[:space:]]` boundaries
- Use `_hooker_json_escape`, `_hooker_json_field`, `_hooker_reverse` from helpers.sh
- JSON field extraction: `echo "$INPUT" | sed -n 's/.*"field"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1`

**Environment variables (no JSON parsing needed):**
- `$HOOKER_EVENT` — hook event name
- `$HOOKER_TRANSCRIPT` — path to transcript JSONL
- `$HOOKER_CWD` — working directory
- `$HOOKER_HELPERS` — path to helpers.sh

## Steps

### 1. Validate hook name
Known hooks: SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure, Notification, SubagentStart, SubagentStop, Stop, TeammateIdle, TaskCompleted, InstructionsLoaded, ConfigChange, WorktreeCreate, WorktreeRemove, PreCompact, PostCompact, Elicitation, ElicitationResult, SessionEnd

If no hook name provided, ask user. Group by category:
- **Session**: SessionStart, SessionEnd, InstructionsLoaded
- **Tools**: PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest
- **Flow**: UserPromptSubmit, Stop, TaskCompleted
- **Agents**: SubagentStart, SubagentStop, TeammateIdle
- **Compact**: PreCompact, PostCompact
- **Config**: ConfigChange, WorktreeCreate, WorktreeRemove
- **MCP**: Elicitation, ElicitationResult
- **Other**: Notification

### 2. Ask what user wants to achieve
Don't ask for "type" directly — ask what they want to happen. Based on the answer, choose the best mode:

- **Static content injection** → Mode 1 (template only)
  - "Dodaj kontekst na starcie sesji" → `SessionStart.md` with `type: inject`
- **Conditional action** → Mode 2 (template + match script)
  - "Przypominaj o docs ale tylko gdy zmieniałem pliki" → `Stop.md` (remind) + `Stop.match.sh`
- **Dynamic content / file reading / complex logic** → Mode 3 (standalone match script)
  - "Wstrzyknij CLAUDE.md do subagentów" → `SubagentStart.match.sh` with `inject "$(cat CLAUDE.md)"`
  - "Blokuj deploy w piątki" → `PreToolUse.match.sh` with date check + `deny`

### 3. Example match scripts with helpers

**Dynamic file injection (e.g. inject CLAUDE.md into subagents):**
```bash
#!/bin/bash
source "${HOOKER_HELPERS}"
CLAUDE_MD=$(cat CLAUDE.md 2>/dev/null || true)
[ -z "$CLAUDE_MD" ] && exit 1
inject "$CLAUDE_MD"
exit 0
```

**Conditional deny (visible message):**
```bash
#!/bin/bash
source "${HOOKER_HELPERS}"
INPUT=$(cat)
CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
DAY=$(date +%u)
if [ "$DAY" = "5" ] && echo "$CMD" | grep -qi 'deploy\|push'; then
    deny "Friday — no deploys. Suggest an alternative for Monday."
    exit 0
fi
exit 1
```

**Remind with messages from yml (visible):**
```bash
#!/bin/bash
source "${HOOKER_HELPERS}"
# Only fire if files were modified in last turn
[ -z "$HOOKER_TRANSCRIPT" ] || [ ! -f "$HOOKER_TRANSCRIPT" ] && exit 1
LAST_TURN=$(awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}' "$HOOKER_TRANSCRIPT" \
    | sed -n '1,/"type"[[:space:]]*:[[:space:]]*"user"/p' 2>/dev/null) || true
echo "$LAST_TURN" | grep -q '"name"[[:space:]]*:[[:space:]]*"\(Edit\|Write\|NotebookEdit\)"' || exit 1
# Load message from yml (user-editable), with fallback
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSGS_FILE=".claude/hooker/my-recipe.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"
MSG=$(sed -n 's/^default:[[:space:]]*"\{0,1\}\([^"]*\).*/\1/p' "$MSGS_FILE" 2>/dev/null | head -1)
[ -z "$MSG" ] && MSG="Did you update docs, tests, and clean up TODOs?"
remind "$MSG"
exit 0
```

### 4. Create files

1. `mkdir -p .claude/hooker`
2. Depending on mode:
   - Mode 1: Write `.claude/hooker/{HookName}.md` only
   - Mode 2: Write `.claude/hooker/{HookName}.md` + `.claude/hooker/{HookName}.match.sh`
   - Mode 3: Write `.claude/hooker/{HookName}.match.sh` only
3. `chmod +x` any `.match.sh` files

### 5. TEST

**Critical.** After creating, test immediately:

1. Find transcript:
   ```bash
   ls -t ~/.claude/projects/*/transcript.jsonl 2>/dev/null | head -1
   ```

2. Test match script standalone:
   ```bash
   echo '{"hook_event_name": "{HookName}", "transcript_path": "/path/to/transcript.jsonl", "session_id": "test", "cwd": "'$(pwd)'"}' \
     | HOOKER_HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/helpers.sh" \
       HOOKER_EVENT="{HookName}" \
       HOOKER_CWD="$(pwd)" \
       HOOKER_TRANSCRIPT="/path/to/transcript.jsonl" \
       .claude/hooker/{HookName}.match.sh
   echo "Exit code: $?"
   ```

3. Full integration test through inject.sh:
   ```bash
   echo '{"hook_event_name": "{HookName}", "transcript_path": "/path/to/transcript.jsonl", "session_id": "test", "cwd": "'$(pwd)'"}' \
     | CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/inject.sh"
   ```

4. Show test result. Fix and re-test if needed.

### 6. Confirm
Show the user what was created and remind:
- Project-level `.claude/hooker/` overrides plugin defaults in `templates/`
- Files can be edited anytime
- `chmod +x` is required for `.match.sh` files

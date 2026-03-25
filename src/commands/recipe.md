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
1. **Detect project stack** — check for `package.json`, `pyproject.toml`, `go.mod`, `Gemfile`,
   `composer.json`, etc. to understand the project's primary language
2. Figure out which hook event(s) are needed
3. Check if an existing recipe covers this — if so, offer to install it
4. **Choose hook language** based on this priority:
   - If the user explicitly asked for a language → use it
   - If the hook needs language-specific tooling (AST parsing, type checking, import analysis)
     → use the project's language (Python hook for Python project, JS hook for JS project)
   - If the hook is simple (pattern matching, file checks, git operations) → bash is fine
   - When in doubt, **ask the user**: "W jakim języku chcesz hook? Bash jest najprostszy,
     ale mogę napisać w Pythonie/JS/TS jeśli wolisz"
5. Decide the best mode (static template, conditional, or dynamic match script)
6. Create the files in `.claude/hooker/`
7. Test it

**Language choice guide:**
| Use case | Recommended | Why |
|----------|-------------|-----|
| Simple guards (block command, check filename) | Bash | Zero deps, fastest, works everywhere |
| AST analysis, code parsing, refactoring | Project's language (Python/JS/TS) | Native AST tools, better accuracy |
| External API calls, complex JSON | Python or JS | Better HTTP/JSON libraries |
| Team hooks (shared in repo) | Whatever the team writes | Lower barrier for maintenance |
| Performance-critical (many files) | Go or compiled | Faster execution |

**Advanced custom hooks** — some requests go beyond pre-built recipes. Examples:
- "after moving a function between files, update imports" — custom PostToolUse hook
  that detects symbol moves via Edit tool tracking or shell command convention, then updates
  imports. Ask about language, detection mode, and generate project-specific hook.
- "after every PR code review, check if CI passed" — custom hook combining
  PostToolUse + external API calls.
- "auto-generate test stubs for new files" — PostToolUse on Write, generates test stubs.

For these, don't look for a matching recipe — generate a custom hook tailored to the project.
Ask the user about shared vs local installation.

**Scheduled tasks (auto-dream / Dreamer pattern)** — `/schedule` exists in Claude Code Desktop
(Cowork mode) but is buggy and not available in CLI. For CLI/Linux, use `cron + claude -p`:
(see: https://code.claude.com/docs/en/scheduled-tasks,
https://github.com/ojowwalker77/Claude-Matrix, https://github.com/jshchnz/claude-code-scheduler)

When the user wants automated recurring tasks (nightly code review, dependency audit, etc.):
1. Generate a cron job template using `claude -p "<prompt>"` in headless mode
2. Installed hooker recipes will be active during scheduled runs
3. Use git worktree for isolation if the task modifies code
4. Install `scheduled-tasks` recipe — auto-syncs crontab from schedules.yml on session start
5. Example: `0 3 * * * cd /project && claude -p "review changes since yesterday, write results to .claude/hooker/cron-results/"`

If the user wants to define schedules in project config, help them create
`.claude/hooker/schedules.yml` (see `${CLAUDE_PLUGIN_ROOT}/recipes/scheduled-tasks/schedules.example.yml`).
Then run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-cron.sh` to install/update crontab
entries automatically. The script uses `@hooker-start/@hooker-end` markers per project
directory — re-running replaces entries for the current project only.

**schedules.yml format:**
```yaml
schedules:
  - name: quick-check
    cron: "0 9 * * *"
    prompt: "Run tests"                    # inline one-liner
  - name: nightly-review
    cron: "0 3 * * *"
    prompt_file: .claude/hooker/prompts/nightly-review.md  # complex multi-line prompt
```
`prompt_file` points to a markdown file with full instructions (checklists, output format,
multi-step workflows). `prompt` is for simple one-liners. `prompt_file` takes precedence.
Help the user write the prompt file when they describe complex scheduled tasks.

**recipe.json `"cron"` field** — indicates if a recipe is useful in headless/scheduled sessions:
- `"cron": true` — safe and useful in cron (safety, refactoring, context, monitoring, formatting)
- `"cron": false` — requires human interaction, skip in cron (behavior-watchdog, skip-acknowledgments,
  remind-to-update-docs — would hang or be useless without a user)

When setting up scheduled tasks, recommend only `cron: true` recipes. When the user asks
"which recipes should I activate for nightly runs?" — filter by this field.

**Cron session tips** — when generating cron prompts, remind the agent:
- Write results to files (e.g. `.claude/hooker/cron-results/review-{date}.md`), not just stdout
- Install `scheduled-tasks` recipe to auto-sync crontab and notify about unread results
- Cron sessions are headless — no TTY, no user to approve permissions. Ensure permissions
  are pre-configured in settings.json for the operations the cron job needs.

## Recipe catalog

Available recipes (no need to scan filesystem — this is the full list):

{% for cat in categories -%}
### {{ cat.Label }}
{% if cat.ID == "safety" -%}
Guardrails and protection rules. No external dependencies — pure bash/sed.
{% elif cat.ID == "refactoring" -%}
Import/link updates after file moves. Two tiers:
- **simple** recipes: pure bash/sed, zero dependencies, work everywhere (including Docker-only envs)
- **smart** recipes: use external tools (typescript, phpactor, rope) for AST-aware accuracy. Falls back to sed if tool unavailable. For projects with multiple smart recipes on the same hook (PostToolUse), consider **isolated mode** installation to avoid merging conflicts.
{% elif cat.ID == "workflow" -%}
Git operations, formatting, changelog enforcement. No external dependencies.
{% elif cat.ID == "context" -%}
Session context injection and preservation across compaction.
{% elif cat.ID == "quality" -%}
Code quality checks and behavioral nudges.
{% elif cat.ID == "monitoring" -%}
Session lifecycle management and observation.
{% endif -%}

| Recipe | Hook | Description |
|--------|------|-------------|
{%- for r in cat.Recipes %}
| `{{ r.ID }}` | {{ r.Hooks | join(d=", ") }} | {{ r.Description }} |
{%- endfor %}

{% endfor -%}

**Hooks without recipes**: {{ uncoveredHooks | join(d=", ") }}

## Without arguments
1. **Detect project context:**
   - Check project stack (package.json, pyproject.toml, go.mod, etc.)
   - Check `.claude/hooker/` for already installed recipes:
     - **Isolated/standalone**: subdirectories in `.claude/hooker/*/`
     - **Merged mode**: grep for `# @recipe` markers in `.claude/hooker/*.match.*`
   - Check `.claude/hooker/runtimes.conf` for configured runtimes
2. Show the catalog with [installed] / [ready] status
3. Based on project stack, **highlight relevant recipes** (e.g. TS refactoring recipes for Node
   projects, Python smart recipes for Python projects)
4. Ask user which recipe(s) to install
5. If user wants custom hooks, ask about preferred language and generate accordingly

## Shared vs Local installation

Before choosing a mode, ask if the recipe should be **shared** (committed to repo) or **local** (per-developer, not committed):

- **Shared**: files in `.claude/hooker/{recipe}/`, hooks in `.claude/settings.json` — version-controlled, team-wide
- **Local**: files in `.claude/hooker/local/{recipe}/`, hooks in `.claude/settings.local.json` — gitignored, personal

When installing local recipes:
1. Ensure `.claude/hooker/.gitignore` exists with `local/` entry (create if not)
2. Put recipe files in `.claude/hooker/local/{recipe-name}/`
3. Wire hooks in `.claude/settings.local.json` (not settings.json)

## Async hooks

Hooks can run asynchronously — Claude Code starts the hook and continues working without
waiting. Output is delivered on the next conversation turn.

**In settings.json:** add `"async": true` and optionally `"timeout": N` (seconds):
```json
{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "...", "async": true, "timeout": 60 }] }
```

**Constraints:** async hooks CANNOT block/deny/remind — only inject/warn/context.

**recipe.json `"async"` field** maps hook names to boolean. When wiring hooks in settings.json,
use this field to determine if a hook should be async:
- `"async": {"PostToolUse": true}` → wire PostToolUse with `"async": true`
- Hooks not listed or set to false → wire as synchronous (default)

**Rule of thumb:** if the hook is render-blocking (CPU heavy, execution time scales with
project size — e.g. `find`, `grep -r`, AST parsing, external tool invocation), recommend async.
If the hook must produce a decision before Claude continues, it must be sync.

**Async must NOT be used when:** the hook returns deny/block/remind/allow decisions
(PreToolUse safety, Stop reminders) — these must complete before Claude acts.
SessionStart/PostCompact context injection should also be sync so context is available immediately.

**Important:** async hooks are best for **fire-and-forget side effects** (file cleanup, import
updates on disk, running formatters). Output delivery back to the agent (systemMessage,
additionalContext) has not been reliably observed — don't rely on async hooks to inject
context or messages. If the agent needs to see the result, use sync.

**Workaround — deferred message delivery:** if an async hook needs to communicate results
to the agent, it can write to a message file (e.g. `.claude/hooker/.async_messages`).
A sync UserPromptSubmit hook reads the file on the next user message, injects the content,
and clears the file. Pattern:
```bash
# In async hook (e.g. PostToolUse async):
echo "Import update completed: 5 files changed" >> .claude/hooker/.async_messages

# In sync UserPromptSubmit hook:
MSGS=".claude/hooker/.async_messages"
if [ -f "$MSGS" ] && [ -s "$MSGS" ]; then
    source "${HOOKER_HELPERS}"
    inject "$(cat "$MSGS")"
    rm -f "$MSGS"
    exit 0
fi
exit 1
```

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

**settings.json entries (matchers from recipe.json):**
```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooker/run.sh $CLAUDE_PROJECT_DIR/.claude/hooker/refactor-move-ts-smart/PostToolUse" }] },
      { "matcher": "Edit", "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooker/run.sh $CLAUDE_PROJECT_DIR/.claude/hooker/auto-format/PostToolUse" }] }
    ]
  }
}
```

### Standalone mode (recommended for independence)

Each recipe uses pre-compiled standalone executables with helpers inlined. **Zero dependency on hooker plugin at runtime.**

Build system generates:
- `.match.sh` → `.execute.sh` (bash helpers inlined)
- `.match.py` → `.execute.py` (Python helpers inlined, import removed)
- `.match.js` / `.match.ts` → `.execute.js` (JS helpers inlined, require/import removed, namespace prefix stripped)

**How it works:**
- Files go in `.claude/hooker/{recipe-name}/` (execute.* + supporting files)
- Hook entries point directly to the executable in `.claude/settings.json`
- Matchers from recipe.json `"matchers"` field filter which tools trigger each hook
- No run.sh, no inject.sh, no plugin cache lookup

**Pros:** Completely independent of hooker. Works even if hooker is uninstalled. No fragile cache paths. Matchers prevent unnecessary script invocations.
**Cons:** Executable files are larger (helpers inlined). Updating helpers requires recompiling. No hooker logging/management.

**Structure:**
```
.claude/hooker/
  refactor-move-ts-smart/
    PostToolUse.execute.sh           ← self-contained bash (helpers inlined)
    SessionStart.execute.sh          ← compiled from .md template
    update-imports.cjs               ← supporting file
    messages.yml                     ← user-editable messages
  my-python-recipe/
    PostToolUse.execute.py           ← self-contained Python (helpers inlined)
  my-js-recipe/
    PreToolUse.execute.js            ← self-contained JS (helpers inlined)
```

**settings.json entries (matchers from recipe.json):**
```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooker/refactor-move-ts-smart/PostToolUse.execute.sh" }] },
      { "matcher": "Edit", "hooks": [{ "type": "command", "command": "python3 $CLAUDE_PROJECT_DIR/.claude/hooker/my-python-recipe/PostToolUse.execute.py" }] }
    ],
    "PreToolUse": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "node $CLAUDE_PROJECT_DIR/.claude/hooker/my-js-recipe/PreToolUse.execute.js" }] }
    ]
  }
}
```

**Note:** shell executables run directly (`PostToolUse.execute.sh`), non-shell need their runtime prefix (`python3 ...`, `node ...`). The runtime is determined during installation.

### Decision guide (present to user)

| | Merged (stable) | Isolated (experimental) | Standalone (independent) |
|---|---|---|---|
| Multiple recipes, same hook | Merged into one script | Each runs independently | Each runs independently |
| `.md` templates | Only one per hook (must inline) | Each recipe keeps its own | Compiled into execute.sh |
| Supporting files | Prefixed: `{recipe}.messages.yml` | In subdirectory | In subdirectory |
| Dependency | Hooker plugin (hooks.json) | Hooker plugin + `run.sh` cache lookup | **None** — fully self-contained |
| Stability | Proven, stable | `run.sh` depends on cache paths | Stable — no external dependencies |
| Removal | Delete `@recipe` section | Delete subdir + settings.json entry | Delete subdir + settings.json entry |

**Recommendation:** Use standalone for new installations — zero dependency on hooker at runtime.
Use merged if you want hooker's management features and logging. Use isolated only if you need
hooker's inject.sh features (e.g. template system) with independent recipes.

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
8. Add hook entries to `.claude/settings.json` for each hook in the recipe.
   Use the `matchers` field from recipe.json to set the correct matcher:
   ```json
   { "matcher": "{from recipe.json matchers[HookName]}", "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooker/run.sh $CLAUDE_PROJECT_DIR/.claude/hooker/{recipe-name}/{HookName}" }] }
   ```
9. **Warn the user:** "Isolated mode uses `hooker.env` to find the plugin. After a plugin
   update, the path in `hooker.env` may point to an old cached version — re-run
   `/hooker:recipe install` or edit `.claude/hooker/hooker.env` to refresh it. The fallback
   auto-detection picks the latest version from cache, but this relies on a cache path
   structure not guaranteed by Anthropic."
10. Confirm installation

### Standalone mode installation
1. Read `${CLAUDE_PLUGIN_ROOT}/recipes/{name}/recipe.json` and the recipe's files
2. Show description and hooks
3. Create `.claude/hooker/{recipe-name}/` directory
4. Copy standalone executable files from `${CLAUDE_PLUGIN_ROOT}/recipes/{name}/` into the subdirectory.
   Look for (in order of preference): `*.execute.sh`, `*.execute.py`, `*.execute.js`
5. Copy supporting files (messages.yml, update-imports.cjs, rope-move.py, .md templates — whatever the recipe needs)
6. `chmod +x` all executable files
7. Add hook entries to `.claude/settings.json` for each hook, pointing directly to the executable.
   Use the `matchers` field from recipe.json to set the correct matcher.
   **Shell** executables run directly; **non-shell** need runtime prefix:
   ```json
   // .execute.sh — runs directly
   { "matcher": "...", "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooker/{recipe}/{Hook}.execute.sh" }] }
   // .execute.py — needs python3
   { "matcher": "...", "hooks": [{ "type": "command", "command": "python3 $CLAUDE_PROJECT_DIR/.claude/hooker/{recipe}/{Hook}.execute.py" }] }
   // .execute.js — needs node
   { "matcher": "...", "hooks": [{ "type": "command", "command": "node $CLAUDE_PROJECT_DIR/.claude/hooker/{recipe}/{Hook}.execute.js" }] }
   ```
8. Confirm installation. Note: hooker plugin is not needed at runtime — executables are self-contained.

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

### Mode 3: Standalone match script (`.match.*` with output, no `.md` needed)
Full dynamic control — script decides everything. Uses helpers for output.
**This is the most powerful mode.** The script can read files, check state, build messages dynamically.
Match scripts can be in **any language**: `.match.sh`, `.match.py`, `.match.js`, `.match.ts`, `.match.go`, `.match.php`, etc.
```
.claude/hooker/SubagentStart.match.sh  → reads CLAUDE.md, injects it (bash)
.claude/hooker/PostToolUse.match.py    → AST analysis with Python
.claude/hooker/PreToolUse.match.js     → Node.js guard
```

## Helpers library

### Bash helpers
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

### Python helpers
`from hooker_helpers import read_input, warn, deny, inject, skip`
(inject.sh sets `PYTHONPATH` automatically — import works out of the box)

| Helper | Effect |
|--------|--------|
| `read_input()` | Parse JSON from stdin, returns dict |
| `json_field(data, "field")` | Extract field (checks top-level + tool_input) |
| `warn(msg)`, `deny(msg)`, `allow(msg)`, `ask(msg)` | Same as bash equivalents |
| `block(msg)`, `remind(msg)` | Same as bash equivalents |
| `inject(text)`, `visible(text)`, `context(text)` | Same as bash equivalents |
| `last_turn()` | Get last assistant turn from transcript |
| `skip()`, `match()`, `error(msg)` | Flow control (sys.exit 1/0/2) |

### JavaScript/TypeScript helpers
`const hooker = require('hooker_helpers');`
(inject.sh sets `NODE_PATH` automatically — require works out of the box)

| Helper | Effect |
|--------|--------|
| `hooker.readInput()` | Parse JSON from stdin, returns object |
| `hooker.jsonField(data, "field")` | Extract field (checks top-level + tool_input) |
| `hooker.warn(msg)`, `.deny(msg)`, `.allow(msg)`, `.ask(msg)` | Same as bash equivalents |
| `hooker.block(msg)`, `.remind(msg)` | Same as bash equivalents |
| `hooker.inject(text)`, `.visible(text)`, `.context(text)` | Same as bash equivalents |
| `hooker.lastTurn()` | Get last assistant turn from transcript |
| `hooker.skip()`, `.match()`, `.error(msg)` | Flow control (process.exit 1/0/2) |

### Other languages
No built-in helpers — implement the contract directly:
- Read JSON from stdin
- Print response JSON to stdout (same format as bash/python/js helpers produce)
- Exit 0 = matched, 1 = skip, 2+ = error

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

**Cross-platform rules (MUST follow when writing bash scripts):**
Bash scripts must work on Linux, macOS, and Windows (Git Bash). Rules:
- **NO** `set -euo pipefail` in match scripts — `pipefail` causes SIGPIPE (exit 141) when helper pipelines use `awk '{exit}'`. inject.sh handles exit codes; match scripts should control flow explicitly with `|| exit 1`.
- **NO** `grep -P` or `grep -oP` (PCRE) — use `sed -n 's/.../p'` for extraction, `grep -q` with POSIX patterns for matching
- **NO** `tac` — use `awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}'`
- **NO** `python3` or `perl` — use `awk` and `sed` for text processing
- **NO** `\s` in patterns — use `[[:space:]]`
- **NO** `\b` in patterns — use explicit context or `[[:space:]]` boundaries
- Use `_hooker_json_escape`, `_hooker_json_field`, `_hooker_reverse` from helpers.sh
- JSON field extraction: `echo "$INPUT" | sed -n 's/.*"field"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1`

**Non-shell match scripts** (Python, JS, TS, Go, etc.) are exempt from these rules — they run through configurable runtimes and use their own language features freely.

**Environment variables:**

Claude Code provides (available in ALL modes):
- `$CLAUDE_PROJECT_DIR` — project root (always use this in settings.json paths!)

Hooker inject.sh provides (available in merged/isolated mode only, NOT standalone):
- `$HOOKER_EVENT` — hook event name
- `$HOOKER_TRANSCRIPT` — path to transcript JSONL
- `$HOOKER_CWD` — working directory
- `$HOOKER_HELPERS` — path to helpers.sh (bash)
- `$HOOKER_HELPERS_PY` — path to hooker_helpers.py
- `$HOOKER_HELPERS_JS` — path to hooker_helpers.js
- `$PYTHONPATH` — includes helpers dir (so `from hooker_helpers import ...` works)
- `$NODE_PATH` — includes helpers dir (so `require('hooker_helpers')` works)
- `$HOOKER_PROJECT_DIR` — `~/.claude/projects/-{slug}` path
- `$HOOKER_PROJECT_SLUG` — project slug derived from CWD

Standalone execute.sh preamble provides:
- `$HOOKER_EVENT` — parsed from hook input JSON
- `$HOOKER_CWD` — parsed from hook input JSON
- `$HOOKER_TRANSCRIPT` — parsed from hook input JSON
- `$CLAUDE_PROJECT_DIR` — set by Claude Code (not by hooker)
- NO `$HOOKER_HELPERS` — helpers are inlined, no need to source

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

**Python match script example:**
```python
#!/usr/bin/env python3
from hooker_helpers import read_input, warn, deny, skip, json_field

data = read_input()
tool = json_field(data, "tool_name")

if tool == "Edit":
    file_path = json_field(data, "file_path") or "unknown"
    warn(f"Edit detected on {file_path}")
else:
    skip()
```

**JavaScript match script example:**
```javascript
const hooker = require('hooker_helpers');
const data = hooker.readInput();

if (data.tool_name === 'Write' && (data.file_path || '').endsWith('.env')) {
    hooker.deny('Cannot write to .env files');
} else {
    hooker.skip();
}
```

**Runtime configuration** — by default: `.py`→`python3`, `.js`→`node`, `.ts`→`npx tsx`.
Users can override runtimes in `.claude/hooker/runtimes.conf`:
```
ts=deno run --allow-read --allow-env
py=docker run --rm -i python:3.12 python3
js=bun run
```
Or via environment: `HOOKER_RUNTIME_ts=bun run`

### 4. Create files

1. `mkdir -p .claude/hooker`
2. Depending on mode:
   - Mode 1: Write `.claude/hooker/{HookName}.md` only
   - Mode 2: Write `.claude/hooker/{HookName}.md` + `.claude/hooker/{HookName}.match.sh`
   - Mode 3: Write `.claude/hooker/{HookName}.match.{ext}` (`.sh`, `.py`, `.js`, `.ts`, etc.)
3. `chmod +x` any `.match.sh` files (non-shell scripts don't need +x — runtime handles them)
4. For non-shell hooks: verify the runtime is available (`python3 --version`, `node --version`, etc.)
   If not, warn the user and suggest installing it or using bash instead.
5. For non-shell hooks in merged/isolated mode: no extra config needed — inject.sh detects
   the extension and uses the default runtime. For custom runtimes, create `.claude/hooker/runtimes.conf`.

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

3. For non-shell match scripts, test standalone:
   ```bash
   # Python
   echo '{"hook_event_name": "{HookName}", "tool_name": "Edit", "cwd": "'$(pwd)'"}' \
     | HOOKER_EVENT="{HookName}" PYTHONPATH="${CLAUDE_PLUGIN_ROOT}/helpers" \
       python3 .claude/hooker/{HookName}.match.py

   # JavaScript
   echo '{"hook_event_name": "{HookName}", "tool_name": "Edit", "cwd": "'$(pwd)'"}' \
     | HOOKER_EVENT="{HookName}" NODE_PATH="${CLAUDE_PLUGIN_ROOT}/helpers" \
       node .claude/hooker/{HookName}.match.js
   ```

4. Full integration test through inject.sh (works for any language):
   ```bash
   echo '{"hook_event_name": "{HookName}", "transcript_path": "/path/to/transcript.jsonl", "session_id": "test", "cwd": "'$(pwd)'"}' \
     | CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/inject.sh"
   ```

5. Show test result. Fix and re-test if needed.

### 6. Confirm
Show the user what was created and remind:
- Project-level `.claude/hooker/` overrides plugin defaults in `templates/`
- Files can be edited anytime
- `chmod +x` is required for `.match.sh` files

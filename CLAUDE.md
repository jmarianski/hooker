# Claude Code Instructions

## Versioning

When pushing changes, bump the version in the relevant plugin's `plugin.json`:
- Hooker: `src/hooker/plugin.json`
- Cache Catcher: `src/cache-catcher/plugin.json`

Use semantic versioning:
- Patch (0.1.0 → 0.1.1): bug fixes, minor tweaks
- Minor (0.1.0 → 0.2.0): new features, new templates
- Major (0.0.x → 1.0.0): breaking changes

## Structure

**⚠ DO NOT edit files outside `src/` directly** — `hooker/` and `cache-catcher/` are auto-generated build outputs.
All changes go into `src/`, then `cd src && go run .` regenerates everything.

### Repo layout (3 top-level dirs)

- `src/` — all source code + build system
- `hooker/` — build output (hooker plugin)
- `cache-catcher/` — build output (cache-catcher plugin)
- `marketplace.json` — shared marketplace (build output)

### Source layout (src/)

- `src/build.go` — build system (`--plugin hooker|cache-catcher|all`)
- `src/generators/*.go` — Go functions providing template variables
- `src/hooker/` — hooker plugin sources:
  - `commands/*.md` — skill templates (Gonja/Jinja2) → `hooker/commands/`
  - `scripts/*.sh` — shell scripts with `# @bundle` includes → `hooker/scripts/`
  - `scripts/helpers/` — modular helper functions bundled into `scripts/helpers.sh`
  - `helpers/` — multi-language helper libraries (Python, JS) → `hooker/helpers/`
  - `recipes/` — pre-built hook configurations → `hooker/recipes/`
  - `hooks/` — hooks.json → `hooker/hooks/`
  - `templates/` — default templates → `hooker/templates/`
  - `plugin.json`, `.pluginignore`, `README.md`
- `src/cache-catcher/` — cache-catcher plugin sources:
  - `match.sh` — standalone hook script → `cache-catcher/match.sh`
  - `hooks/hooks.json` — just PostToolUse → `cache-catcher/hooks/`
  - `scripts/cache-catcher.sh` — CLI tool → `cache-catcher/scripts/`
  - `config.yml`, `messages.yml`, `plugin.json`, `.pluginignore`, `README.md`

## Cross-platform

All shell scripts must work on Linux, macOS, and Windows (Git Bash).
No `grep -P`, `tac`, `python3`, `perl` in shell scripts. Use POSIX grep/sed/awk only.
Non-shell match scripts (Python, JS, etc.) are exempt — they run through configurable runtimes.

## Template format

Templates use YAML frontmatter with `type` field:
- `inject` (default) — injects content into Claude's context
- `remind` — blocks stop with reminder (loop-safe via inject.sh)
- `block` — always blocks with reason
- `allow` / `deny` — PreToolUse permission decisions
- `context` — adds as additionalContext JSON

## Recipe structure

Each recipe lives in `src/hooker/recipes/{recipe-name}/` with these files:

- `recipe.json` — metadata (required):
  ```json
  {
    "name": "Human-Readable Name",
    "description": "One-line description of what it does.",
    "hooks": ["PostToolUse"],
    "category": "refactoring",
    "dependencies": ["ts-morph (npm)"],
    "attribution": {
      "type": "original|inspired|adapted",
      "author": "Author Name",
      "license": "MIT",
      "url": "https://..."
    }
  }
  ```
  When installing a recipe (any mode), the skill should add `"installed_from": "hooker@X.Y.Z"`
  to the project's copy of recipe.json. This lets users check if their installed recipes
  are outdated compared to the current hooker version.
- `{HookName}.match.*` — match script in any language (one per hook per recipe):
  - `.match.sh` — Bash (default, backward compatible)
  - `.match.py` — Python (uses `python3` by default)
  - `.match.js` — JavaScript (uses `node` by default)
  - `.match.ts` — TypeScript (uses `npx tsx` by default)
  - `.match.go`, `.match.php`, `.match.rb`, `.match.pl` — or any other extension
  - Runtime per extension is configurable via `runtimes.conf` or `HOOKER_RUNTIME_<ext>` env vars
- `messages.yml` — user-customizable messages/strings (optional)

**Categories** (used for grouping in README/recipe catalog):
- `safety` — guardrails, blocking dangerous commands, protecting files
- `refactoring` — code moves, import updates, rename support
- `workflow` — git operations, formatting, changelog enforcement
- `context` — session context injection, compaction, re-injection
- `quality` — code quality checks, lazy code detection, docs reminders
- `monitoring` — behavior watchdog, session notes, lifecycle management

**Fields in recipe.json:**
- `hooks` — array of hook names this recipe uses
- `category` — one of the categories above
- `dependencies` — optional array of external tools needed (e.g. `["ts-morph (npm)"]`)
- `attribution.type`: `original` (we wrote it), `inspired` (clean-room from idea), `adapted` (derived from code)

## Gotchas

- **Match script exit codes**: `exit 0` = matched, `exit 1` = no match (silent skip),
  `exit 2+` = error/crash (inject.sh warns agent with error details via hidden inject).
  Match scripts should use `exit 1` for intentional skips, never `exit 2+` unless something
  actually broke. This lets inject.sh distinguish "not relevant" from "broken".
- **No `set -euo pipefail` in match scripts** — `pipefail` causes SIGPIPE (exit 141) when
  helper pipelines (`_hooker_last_turn`, etc.) use `awk ... | grep ... | awk '{exit}'`.
  inject.sh already handles exit codes; match scripts should control flow explicitly.
- **`remind()` helper = `block()` helper** — both produce identical JSON.
  Loop-safety for Stop hooks is NOT in the helper — it's handled by `inject.sh`
  (checks `stop_hook_active`) or by the match script itself. If writing a Stop
  match script that uses `remind()` directly, add your own `stop_hook_active` check.
- **HOOKER_PROJECT_DIR derivation** — derives `~/.claude/projects/` path from CWD
  by replacing `/` with `-`. Not yet verified on Windows (Git Bash `/c/Users/...` paths).
- **One `.match.*` per hook per directory** — merging recipes means combining logic
  into one script with `@recipe` markers, not having multiple files.
- **Hook event compatibility across CC versions** — Claude Code validates hook event names
  strictly. If `hooks.json` (plugin) or `settings.json` (standalone) contains an event the
  installed CC version doesn't know (e.g. `PostCompact` on CC ≤2.1.x), **all hooks in that
  file are rejected** — not just the unknown one. There is no graceful degradation. When adding
  new hook events to `hooks.json`, be aware that users on older CC versions will get a full
  plugin load failure. Currently no workaround exists (CC doesn't support optional/unknown hooks).
- **Notification/TeammateIdle hooks** — don't build recipes for these. The
  [claude-notifications-go](https://github.com/777genius/claude-notifications-go)
  plugin handles desktop notifications already. Duplicating it would be pointless.

## Async hooks

Hooks can run asynchronously with `"async": true` in settings.json/hooks.json:
```json
{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "...", "async": true, "timeout": 60 }] }
```

**How async works:** Claude Code starts the hook and continues immediately. Output is delivered
on the next conversation turn via `systemMessage` or `additionalContext` JSON fields.

**Constraints:** async hooks CANNOT block/deny/remind — only inject context or warn.

**Rule of thumb:** if the hook is render-blocking (CPU heavy, execution time scales with
project size — e.g. `find`, `grep -r`, AST parsing), use async. If it must produce a
decision before Claude continues (deny, block, remind), it must be sync.

**When NOT to use async:** hooks that return deny/block/remind/allow decisions (PreToolUse
safety, Stop reminders). These must complete before Claude acts.

**Tested behavior (v0.24.0):** async hooks fire and complete correctly, but output delivery
back to the agent (systemMessage/additionalContext) was not observed in testing — the hook
runs, side effects happen (file changes, cleanup), but JSON output may not reach the agent's
context. Use async for **fire-and-forget side effects** (delete files, update imports on disk,
run formatters), not for delivering messages or context to the agent.

recipe.json has `"async"` field (per hook) to indicate recommendation. The skill uses it
when wiring hooks in settings.json.

## Shared vs Local

Recipes can be shared (team-wide) or local (per-developer):
- **Shared**: `.claude/hooker/{recipe}/` + `.claude/settings.json` — committed to repo
- **Local**: `.claude/hooker/local/{recipe}/` + `.claude/settings.local.json` — gitignored

The skill creates `.claude/hooker/.gitignore` with `local/` on first local install.

## Installation modes

Recipes can be installed in three modes:

**Merged (stable, default):** Files in `.claude/hooker/{HookName}.match.sh` with `@recipe`
markers. Multiple recipes for same hook merged into one script. Relies only on plugin hooks.json.

**Isolated (experimental):** Files in `.claude/hooker/{recipe-name}/`. Each recipe = separate
hook command via `.claude/hooker/run.sh` bridge + `.claude/settings.json` entries.
No merging needed. settings.json hooks are official Claude Code functionality, but `run.sh`
relies on finding the hooker plugin in known cache paths (`~/.claude/plugins/cache/...`) and
calling its `inject.sh` — this internal path structure is **not guaranteed by Anthropic** and
may change between Claude Code versions.

**Standalone:** Files in `.claude/hooker/{recipe-name}/` using compiled `*.execute.sh` scripts.
Helpers are inlined, zero runtime dependency on hooker. Wired directly in `.claude/settings.json`.
Build system compiles `match.sh` + helpers → `execute.sh` automatically.

**IMPORTANT:** Always use `$CLAUDE_PROJECT_DIR` in settings.json command paths, not relative
paths. Claude Code sets this env var to the project root when running hooks. Relative paths
break when CWD changes (e.g. `cd apps/api && npm test`).

Always ask user which mode. Warn about isolated mode's cache path dependency.
Recommend standalone for users who want recipes without hooker plugin dependency.

## Multi-language match scripts

Match scripts can be written in any language. The contract is universal:
- Read JSON from stdin
- Write response JSON to stdout
- Exit 0 = matched, 1 = skip, 2+ = error

**Runtime resolution** (how to execute a match script):
- Priority: `HOOKER_RUNTIME_<ext>` env var > project `runtimes.conf` > user `runtimes.conf` > defaults
- Defaults: `sh`→bash, `py`→python3, `js`→node, `ts`→npx tsx, `go`→go run, `php`→php, `rb`→ruby
- Config file: `.claude/hooker/runtimes.conf` or `~/.claude/hooker/runtimes.conf` (format: `ext=command`)
- Empty runtime = execute directly (compiled binary)

**Helper libraries** (optional, for non-shell match scripts):
- `helpers/hooker_helpers.py` — Python: `from hooker_helpers import inject, warn, deny, skip`
- `helpers/hooker_helpers.js` — JS/TS: `const hooker = require('hooker_helpers')`
- inject.sh sets `PYTHONPATH` and `NODE_PATH` so imports work automatically
- Helpers provide: `read_input()`, `inject()`, `warn()`, `deny()`, `allow()`, `block()`, `skip()`, etc.

**Standalone non-shell recipes** — raw match script copied as-is, user manages runtime.
No compilation or helper inlining for non-shell (unlike `.match.sh` → `.execute.sh`).

## Override priority

Project `.claude/hooker/` > User `~/.claude/hooker/` > Plugin `templates/`

## Build

Run `cd src && go run .` to build all plugins from sources.

```bash
cd src && go run .                        # build all (default)
cd src && go run . --plugin hooker        # build hooker only
cd src && go run . --plugin cache-catcher # build cache-catcher only
```

The builder for hooker:
- **Commands**: Gonja templates (`src/hooker/commands/`) → `hooker/commands/`
- **Scripts**: Shell bundling (`# @bundle` directives) → `hooker/scripts/`
- **Recipes**: Copy + compile standalone executables → `hooker/recipes/`
- **Static files**: hooks, templates, helpers, plugin.json, .pluginignore

The builder for cache-catcher:
- **match.sh**: Copied as-is (self-contained) → `cache-catcher/match.sh`
- **Static files**: hooks.json, CLI script, config, messages, plugin.json

Shared: `marketplace.json` → repo root (reads versions from both plugin.json files).

Generator functions in `src/generators/*.go` provide template variables.

**After ANY change in src/:** run `cd src && go run .` before committing.

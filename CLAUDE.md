# Claude Code Instructions

## Versioning

When pushing changes to skills (`commands/*.md`) or shell scripts (`scripts/*.sh`), always bump the version in:
- `.claude-plugin/plugin.json`

Use semantic versioning:
- Patch (0.1.0 → 0.1.1): bug fixes, minor tweaks
- Minor (0.1.0 → 0.2.0): new features, new templates
- Major (0.0.x → 1.0.0): breaking changes

## Structure

**⚠ DO NOT edit files outside `src/` directly** — they are auto-generated build outputs.
All changes go into `src/`, then `cd src && go run .` regenerates everything.
Editing root files directly will be overwritten on next build.

- `src/commands/*.md` — skill templates (Gonja/Jinja2) → `commands/`
- `src/scripts/*.sh` — shell scripts with `# @bundle` includes → `scripts/`
- `src/scripts/helpers/` — modular helper functions bundled into `scripts/helpers.sh`
- `src/recipes/` — pre-built hook configurations → `recipes/`
- `src/hooks/` — hooks.json → `hooks/`
- `src/templates/` — default templates → `templates/`
- `src/generators/*.go` — Go functions providing template variables

## Cross-platform

All scripts must work on Linux, macOS, and Windows (Git Bash).
No `grep -P`, `tac`, `python3`, `perl`. Use POSIX grep/sed/awk only.

## Template format

Templates use YAML frontmatter with `type` field:
- `inject` (default) — injects content into Claude's context
- `remind` — blocks stop with reminder (loop-safe via inject.sh)
- `block` — always blocks with reason
- `allow` / `deny` — PreToolUse permission decisions
- `context` — adds as additionalContext JSON

## Recipe structure

Each recipe lives in `src/recipes/{recipe-name}/` with these files:

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
- `{HookName}.match.sh` — bash match script (one per hook)
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
- **`remind()` helper = `block()` helper** — both produce identical JSON.
  Loop-safety for Stop hooks is NOT in the helper — it's handled by `inject.sh`
  (checks `stop_hook_active`) or by the match script itself. If writing a Stop
  match script that uses `remind()` directly, add your own `stop_hook_active` check.
- **HOOKER_PROJECT_DIR derivation** — derives `~/.claude/projects/` path from CWD
  by replacing `/` with `-`. Not yet verified on Windows (Git Bash `/c/Users/...` paths).
- **One `.match.sh` per hook per directory** — merging recipes means combining logic
  into one script with `@recipe` markers, not having multiple files.
- **Notification/TeammateIdle hooks** — don't build recipes for these. The
  [claude-notifications-go](https://github.com/777genius/claude-notifications-go)
  plugin handles desktop notifications already. Duplicating it would be pointless.

## Installation modes

Recipes can be installed in two modes:

**Merged (stable, default):** Files in `.claude/hooker/{HookName}.match.sh` with `@recipe`
markers. Multiple recipes for same hook merged into one script. Relies only on plugin hooks.json.

**Isolated (experimental):** Files in `.claude/hooker/{recipe-name}/`. Each recipe = separate
hook command via `.claude/hooker/run.sh` bridge + `.claude/settings.json` entries.
No merging needed. settings.json hooks are official Claude Code functionality, but `run.sh`
relies on finding the hooker plugin in known cache paths (`~/.claude/plugins/cache/...`) and
calling its `inject.sh` — this internal path structure is **not guaranteed by Anthropic** and
may change between Claude Code versions.

Always ask user which mode. Always warn about isolated mode's experimental nature.

## Override priority

Project `.claude/hooker/` > User `~/.claude/hooker/` > Plugin `templates/`

## Build

Run `cd src && go run .` to build all plugin files from sources.

The builder:
- **Commands**: Gonja templates (`src/commands/`) → `commands/`
- **Scripts**: Shell bundling (`# @bundle` directives) → `scripts/`
- **Static files**: Copies recipes, hooks, templates, plugin.json, .pluginignore

Generator functions in `src/generators/*.go` provide template variables.

**After ANY change in src/:** run `cd src && go run .` before committing.

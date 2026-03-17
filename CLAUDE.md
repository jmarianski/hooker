# Claude Code Instructions

## Versioning

When pushing changes to skills (`commands/*.md`) or shell scripts (`scripts/*.sh`), always bump the version in:
- `.claude-plugin/plugin.json`

Use semantic versioning:
- Patch (0.1.0 → 0.1.1): bug fixes, minor tweaks
- Minor (0.1.0 → 0.2.0): new features, new templates
- Major (0.0.x → 1.0.0): breaking changes

## Structure

Everything outside `src/` is a **build output**. Edit sources in `src/`, run the builder.

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
- `remind` — blocks stop with reminder (loop-safe)
- `block` — always blocks with reason
- `allow` / `deny` — PreToolUse permission decisions
- `context` — adds as additionalContext JSON

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

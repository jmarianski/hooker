# Claude Code Instructions

## Versioning

When pushing changes to skills (`commands/*.md`) or shell scripts (`scripts/*.sh`), always bump the version in:
- `.claude-plugin/plugin.json`

Use semantic versioning:
- Patch (0.1.0 → 0.1.1): bug fixes, minor tweaks
- Minor (0.1.0 → 0.2.0): new features, new templates
- Major (0.0.x → 1.0.0): breaking changes

## Structure

- `hooks/hooks.json` — registers all 21 hooks pointing to `scripts/inject.sh`
- `scripts/inject.sh` — universal handler, reads template based on hook event name
- `scripts/helpers.sh` — portable helper functions for match scripts
- `templates/*.md` — default templates (filename = hook event name)
- `commands/*.md` — user-facing skills (/hooker:config, /hooker:status, /hooker:recipe)
- `recipes/` — pre-built hook configurations
- `src/` — build sources, NOT part of the runtime plugin (see `.pluginignore`)

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

Skills with dynamic content have source templates in `src/commands/`.
Run `bash src/build.sh` to compile them → `commands/`.

The build script copies `src/commands/*.md` to `commands/`, replacing content between
`<!-- BUILD:*:START -->` / `<!-- BUILD:*:END -->` markers with generated data.

Static skills (config.md, status.md) live directly in `commands/` — no source needed.

**After adding/changing recipes:** run `bash src/build.sh` before committing.

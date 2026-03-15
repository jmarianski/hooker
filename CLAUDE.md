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
- `templates/*.md` — default templates (filename = hook event name)
- `commands/*.md` — user-facing skills (/hooker:config, /hooker:status, /hooker:enable)

## Template format

Templates use YAML frontmatter with `type` field:
- `inject` (default) — injects content into Claude's context
- `remind` — blocks stop with reminder (loop-safe)
- `block` — always blocks with reason
- `allow` / `deny` — PreToolUse permission decisions
- `context` — adds as additionalContext JSON

## Override priority

Project `.claude/hooker/{HookName}.md` > Plugin `templates/{HookName}.md`

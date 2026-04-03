# hooker-marketplace

Two Claude Code plugins from one [marketplace](https://gitlab.com/treetank/hooker).

## Hooker

Universal hook injection framework for Claude Code. React to any of 25+ hook events
(tool use, session start, compaction, stop, etc.) with simple shell/Python/JS scripts.

- **34 pre-built recipes** — safety guardrails, refactoring helpers, context injection, code quality checks
- **Three install modes** — merged (stable), isolated, standalone (zero plugin dependency)
- **Multi-language match scripts** — bash, Python, JS, TS, Go, PHP, Ruby
- **Template system** — YAML frontmatter with inject/warn/block/deny/allow actions

Full docs: [`hooker/README.md`](hooker/README.md)

## Cache Catcher

Monitors Claude Code prompt cache health in real time. Detects when `cache_creation`
consistently exceeds `cache_read` — a sign of broken caching that silently multiplies API costs.

- **PostToolUse hook** — analyzes transcript after each tool use, warns or stops the agent
- **Resume detection** — distinguishes expected cache rebuilds (>1h gap) from bugs (<1h)
- **Built-in CLI** — type `cache-catcher status` directly in Claude Code (zero API cost)
- **Configurable** — warn vs block mode, thresholds, cooldown, custom aliases (`cc status`)

Full docs: [`cache-catcher/README.md`](cache-catcher/README.md)

## Install

```bash
/plugin marketplace add https://gitlab.com/treetank/hooker.git
/plugin install hooker@hooker-marketplace
/plugin install cache-catcher@hooker-marketplace
```

## Contributing

Source of truth is `src/`; top-level `hooker/` and `cache-catcher/` are build outputs.
See [`CLAUDE.md`](CLAUDE.md) for structure, build system, and versioning rules.

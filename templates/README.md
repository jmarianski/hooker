# templates/ (intentionally empty)

Plugin-level hook templates. Any `.md` or `.match.sh` file placed here will be **active for all projects** immediately after plugin install — no user action needed.

This directory is intentionally empty. Hooker is a framework, not an opinionated defaults package. Users choose what to enable via `/hooker:recipe install <name>`, which copies files to the project-level `.claude/hooker/` directory.

Auto-loading makes sense for plugins like [kompakt](https://gitlab.com/treetank/kompakt) where the whole point is a single behavior (custom compaction prompt). It doesn't make sense here — Hooker covers 21 hook events with 11+ recipes, and auto-activating any of them would be a surprise.

## If you want global hooks

Place files directly in this directory (after install, in the plugin cache). They'll apply to every project. But consider using `.claude/hooker/` per-project instead — it's explicit, version-controllable, and doesn't break when the plugin updates.

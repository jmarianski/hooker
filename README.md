# hooker (monorepo)

This repository publishes **two** Claude Code plugins from one [marketplace](https://gitlab.com/treetank/hooker):

| Plugin | Purpose |
|--------|---------|
| **hooker** | Hook injection framework (recipes, merged hooks, standalone builds). |
| **cache-catcher** | Prompt-cache health: warns or blocks when cache writes dominate reads. |

## Install (Claude Code)

Marketplace id matches the repo: **`hooker-marketplace`** (see `.claude-plugin/marketplace.json`).

```bash
/plugin marketplace add https://gitlab.com/treetank/hooker.git
/plugin install hooker@hooker-marketplace
/plugin install cache-catcher@hooker-marketplace
```

## Documentation

- **hooker** — [`hooker/README.md`](hooker/README.md) (built from `src/hooker/`)
- **cache-catcher** — [`cache-catcher/README.md`](cache-catcher/README.md) (built from `src/cache-catcher/`)
- **Contributing / layout** — [`CLAUDE.md`](CLAUDE.md)

Source of truth for plugin sources is **`src/`**; top-level `hooker/` and `cache-catcher/` are build outputs (`cd src && go run .`).

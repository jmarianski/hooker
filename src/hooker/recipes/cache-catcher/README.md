# Cache Catcher

Monitor Claude Code prompt cache health in real time. Detects when `cache_creation_input_tokens` consistently exceeds `cache_read_input_tokens` — a sign of broken prompt caching that silently multiplies API costs.

## Installation

```bash
/plugin marketplace add https://gitlab.com/treetank/hooker.git
/plugin install cache-catcher@hooker-marketplace
```

## How it works

After each tool use, Cache Catcher reads the session transcript and compares cache write vs read tokens in recent turns. If writes consistently exceed reads (configurable threshold), it warns the agent or blocks further tool use.

## CLI

Invoke the bundled script (path depends on plugin install, often under `~/.claude/plugins/cache/.../scripts/cache-catcher.sh`). With no arguments it prints command help.

```bash
# List commands (same as: cache-catcher.sh help)
cache-catcher.sh

# Show current session cache health
cache-catcher.sh status

# Per-turn cache metrics
cache-catcher.sh history

# All sessions overview (status uses the last 10 assistant turns per file; not the whole session)
cache-catcher.sh sessions
cache-catcher.sh sessions -n 20   # wider window for status/ratio columns

# Live monitoring (real terminal only — the Claude Code `cache-catcher watch` prompt shows how to run it in a shell)
cache-catcher.sh watch

# Show configuration (project override vs plugin default)
cache-catcher.sh config
# Or explicitly: cache-catcher.sh config show

# Create project override from plugin template (writes .claude/cache-catcher.config.yml)
cache-catcher.sh -p /path/to/repo config init
cache-catcher.sh -p /path/to/repo config init --force   # overwrite existing

# Read / write single keys (project file; get merges default + override)
cache-catcher.sh -p /path/to/repo config get threshold
cache-catcher.sh -p /path/to/repo config set mode block
cache-catcher.sh -p /path/to/repo config set ignore_first_turn false

# Claude Code prompt prefixes (UserPromptSubmit): always "cache-catcher", plus optional extras
cache-catcher.sh -p /path/to/repo alias              # show built-in + extras from config
cache-catcher.sh -p /path/to/repo alias print        # CSV: cache-catcher[,cc,...]
cache-catcher.sh -p /path/to/repo alias set cc       # also accept "cc,dbg"
cache-catcher.sh -p /path/to/repo alias clear        # drop extras
```

### Options
- `-s, --session ID` — analyze specific session
- `-n, --last N` — last N turns for `status` / `history`; for `sessions`, the window used for Read/Creation/Ratio/Status (default 10)
- `-j, --json` — JSON output
- `-t, --threshold N` — override threshold
- `-p, --project DIR` — project root (where `.claude/` lives). Put **before** the command for `config init|get|set` so paths resolve correctly.

Editable keys for `config get` / `config set`: `mode`, `lookback`, `threshold`, `min_tokens`, `streak`, `cooldown`, `ignore_first_turn`, `prompt_aliases` (comma-separated extra command prefixes for Claude Code; `cache-catcher` is always allowed).

### Develop / test in the hooker repo

```bash
bash src/cache-catcher/scripts/self-test.sh
```

Uses a fake `HOME` and a synthetic transcript; checks `help`, `sessions`, `alias print` / `set`, and `config init` / `set` / `get`.

## Configuration

Defaults ship with the plugin as `config.yml` next to `match.sh` (read-only from your perspective unless you fork the plugin). **Per-project overrides** go in the repo root:

`.claude/cache-catcher.config.yml`

The hook resolves the project directory when Claude Code runs it (typically your project root), so that file is the supported way to change thresholds, mode, etc. Optional: `.claude/cache-catcher.messages.yml` overrides `messages.yml` the same way.

Example override file:

```yaml
mode: warn          # warn or block
lookback: 3         # turns to analyze
threshold: 1.0      # creation/read ratio trigger
min_tokens: 5000    # ignore small writes
streak: 1           # bad turns before trigger
cooldown: 60        # seconds between warnings
ignore_first_turn: true
prompt_aliases: cc    # optional: "cc status" works like "cache-catcher status"
```

## Also available as Hooker recipe

If you use the [Hooker](https://gitlab.com/treetank/hooker) plugin, this is available as the `cache-watchdog` recipe with full integration.

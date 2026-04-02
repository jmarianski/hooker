# Cache Catcher

Monitor Claude Code prompt cache health in real time. Detects when `cache_creation_input_tokens` consistently exceeds `cache_read_input_tokens` — a sign of broken prompt caching that silently multiplies API costs.

## Installation

```bash
/plugin marketplace add https://gitlab.com/treetank/hooker.git
/plugin install cache-catcher@treetank-marketplace
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

# All sessions overview
cache-catcher.sh sessions

# Live monitoring
cache-catcher.sh watch

# Show configuration (project override vs plugin default)
cache-catcher.sh config

# Copy-paste shell alias so you can type cache-catcher
cache-catcher.sh alias
cache-catcher.sh alias print   # one line for scripts
```

### Options
- `-s, --session ID` — analyze specific session
- `-n, --last N` — show last N turns
- `-j, --json` — JSON output
- `-t, --threshold N` — override threshold
- `-p, --project DIR` — project directory

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
```

## Also available as Hooker recipe

If you use the [Hooker](https://gitlab.com/treetank/hooker) plugin, this is available as the `cache-watchdog` recipe with full integration.

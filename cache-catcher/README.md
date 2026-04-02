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

```bash
# Show current session cache health
cache-catcher.sh status

# Per-turn cache metrics
cache-catcher.sh history

# All sessions overview
cache-catcher.sh sessions

# Live monitoring
cache-catcher.sh watch

# Show configuration
cache-catcher.sh config
```

### Options
- `-s, --session ID` — analyze specific session
- `-n, --last N` — show last N turns
- `-j, --json` — JSON output
- `-t, --threshold N` — override threshold
- `-p, --project DIR` — project directory

## Configuration

Create `.claude/cache-catcher.config.yml` in your project:

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

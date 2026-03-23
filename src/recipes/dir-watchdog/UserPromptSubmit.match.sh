#!/bin/bash
# Directory Watchdog — monitor directories for file bloat
# UserPromptSubmit hook: runs periodically on user messages
# Checks configured directories and warns/cleans as needed.
source "${HOOKER_HELPERS}"

INPUT=$(cat)

# Frequency control — don't check every message
RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE=".claude/hooker/dir-watchdog.yml"
FREQ=5

# Read check_frequency from config if available
if [ -f "$CONFIG_FILE" ]; then
    CUSTOM_FREQ=$(sed -n 's/^check_frequency:[[:space:]]*\([0-9]*\)/\1/p' "$CONFIG_FILE" | head -1)
    [ -n "$CUSTOM_FREQ" ] && FREQ="$CUSTOM_FREQ"
fi

# Random check based on frequency (1 in N chance)
if [ "$FREQ" -gt 1 ] 2>/dev/null; then
    RAND=$((RANDOM % FREQ))
    [ "$RAND" -ne 0 ] && exit 1
fi

# Need python3 for YAML parsing and directory scanning
command -v python3 >/dev/null 2>&1 || exit 1

# Run scanner
RESULT=$(python3 "${RECIPE_DIR}/scan-dirs.py" "$CONFIG_FILE" 2>/dev/null)
[ -z "$RESULT" ] || [ "$RESULT" = "[]" ] && exit 1

# Load messages
MSG_WARN=$(sed -n 's/^warn_bloated:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_CLEANUP=$(sed -n 's/^cleanup_done:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_HINT=$(sed -n 's/^no_config_hint:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")

# Parse actions from JSON array — each line is one action object
# Use python3 to extract since bash can't parse JSON arrays
MESSAGES=$(python3 -c "
import sys, json
actions = json.loads(sys.argv[1])
msgs_warn = sys.argv[2]
msgs_cleanup = sys.argv[3]
msgs_hint = sys.argv[4]

output = []
has_unconfigured = False

for a in actions:
    action = a.get('action', '')
    path = a.get('path', '')
    count = a.get('count', 0)
    max_f = a.get('max', 30)
    ext = a.get('ext', '*')

    if action == 'warn':
        msg = msgs_warn.replace('{path}', path).replace('{count}', str(count)).replace('{max}', str(max_f)).replace('{ext}', ext)
        output.append(msg)
    elif action == 'cleanup':
        removed = a.get('removed', 0)
        kept = a.get('kept', 0)
        msg = msgs_cleanup.replace('{path}', path).replace('{removed}', str(removed)).replace('{kept}', str(kept)).replace('{max}', str(max_f)).replace('{ext}', ext)
        output.append(msg)
    elif action == 'warn_unconfigured':
        has_unconfigured = True
        msg = msgs_warn.replace('{path}', path).replace('{count}', str(count)).replace('{max}', str(max_f)).replace('{ext}', ext)
        output.append(msg)

if has_unconfigured:
    output.append(msgs_hint)

print('\n'.join(output))
" "$RESULT" "$MSG_WARN" "$MSG_CLEANUP" "$MSG_HINT" 2>/dev/null)

[ -z "$MESSAGES" ] && exit 1

inject "$MESSAGES"
exit 0

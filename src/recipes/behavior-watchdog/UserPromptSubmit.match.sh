#!/bin/bash
# Behavior Watchdog — silently remind Claude to self-check
# Fires on frustration keywords (always) or randomly (~1 in 8 messages)
source "${HOOKER_HELPERS}"

INPUT=$(cat)

# Extract user prompt
PROMPT=$(echo "$INPUT" | sed -n 's/.*"user_prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$PROMPT" ] && exit 1

# Load config
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSGS_FILE=".claude/hooker/behavior-watchdog.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1 || echo "$2"
}

# Extract keywords from yml (multiline value after "keywords: |")
# Each non-empty, non-comment line is a keyword
KEYWORDS=$(awk '
    /^keywords:/ { capture=1; next }
    capture && /^  / { s=$0; gsub(/^  /, "", s); gsub(/[[:space:]]*$/, "", s); if (s != "" && substr(s,1,1) != "#") print s }
    capture && /^[a-z]/ { exit }
' "$MSGS_FILE" 2>/dev/null)

# Check for frustration signals (case-insensitive)
LOWER_PROMPT=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')
FRUSTRATED=false

while IFS= read -r keyword; do
    [ -z "$keyword" ] && continue
    lower_keyword=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
    case "$LOWER_PROMPT" in
        *"$lower_keyword"*) FRUSTRATED=true; break ;;
    esac
done <<< "$KEYWORDS"

if [ "$FRUSTRATED" = "true" ]; then
    MSG=$(yml_get frustration_check "The user seems frustrated. Check /hooker:recipe for fixes.")
    inject "$MSG"
    exit 0
fi

# Random check (~1 in 8 messages)
RAND=$(awk 'BEGIN{srand(); print int(rand()*8)}')
if [ "$RAND" -eq 0 ]; then
    MSG=$(yml_get random_check "Does the user seem unhappy? Check /hooker:recipe for fixes.")
    inject "$MSG"
    exit 0
fi

exit 1

#!/bin/bash
# Behavior Watchdog — silently remind Claude to self-check
# Fires on frustration keywords (always) or randomly (~1 in 8 messages)
source "${HOOKER_HELPERS}"

INPUT=$(cat)

# Extract user prompt
PROMPT=$(echo "$INPUT" | sed -n 's/.*"user_prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$PROMPT" ] && exit 1

# Load messages
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSGS_FILE=".claude/hooker/behavior-watchdog.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1 || echo "$2"
}

# Check for frustration signals (case-insensitive)
LOWER_PROMPT=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')
FRUSTRATED=false

for word in angry frustrated annoying stop doing that wrong again "not what i" "i said" "already told" "how many times" kurwa cholera "nie to" "przestań" "znowu" "ile razy"; do
    case "$LOWER_PROMPT" in
        *"$word"*) FRUSTRATED=true; break ;;
    esac
done

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

#!/bin/bash
# Refactor Move Symbol — detect function/class moves between files
# PostToolUse hook: fires after Edit tool completes
# Uses Python script for diff analysis and state tracking.
source "${HOOKER_HELPERS}"

INPUT=$(cat)

# Only act on Edit tool
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" = "Edit" ] || exit 1

# Need python3 for analysis
command -v python3 >/dev/null 2>&1 || exit 1

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load messages
MSG_DETECTED=$(sed -n 's/^detected:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_TRACKED=$(sed -n 's/^removal_tracked:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")

# Run detection
RESULT=$(echo "$INPUT" | python3 "${RECIPE_DIR}/detect-move.py" 2>/dev/null)
[ -z "$RESULT" ] && exit 1

ACTION=$(echo "$RESULT" | sed -n 's/.*"action"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

case "$ACTION" in
    move_detected)
        SYMBOL=$(echo "$RESULT" | sed -n 's/.*"symbol"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        FROM=$(echo "$RESULT" | sed -n 's/.*"from"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        TO=$(echo "$RESULT" | sed -n 's/.*"to"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        REFS=$(echo "$RESULT" | sed -n 's/.*"references"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')

        MSG=$(echo "$MSG_DETECTED" | sed "s|{symbol}|$SYMBOL|g; s|{from}|$FROM|g; s|{to}|$TO|g; s|{count}|${REFS:-0}|g")
        inject "$MSG"
        exit 0
        ;;
    removal_tracked)
        # Silent — just tracking, don't bother the agent unless configured to
        exit 1
        ;;
    *)
        exit 1
        ;;
esac

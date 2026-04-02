#!/bin/bash
# Skip acknowledgments — inject instruction to be direct
# Adapted from ChrisWiles/claude-code-showcase (MIT)
source "${HOOKER_HELPERS}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSGS_FILE=".claude/hooker/skip-acknowledgments.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1 || echo "$2"
}

inject "$(yml_get inject_msg "Skip acknowledgments and filler phrases like 'Great question!', 'You're absolutely right!', 'That's a great idea!'. Go straight to the answer or action.")"
exit 0

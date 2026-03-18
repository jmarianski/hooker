#!/bin/bash
# Session Guardian — remind to diagnose failed tools
source "${HOOKER_HELPERS}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSGS_FILE=".claude/hooker/session-guardian.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1 || echo "$2"
}

inject "$(yml_get tool_failure 'A tool just failed. Read the error carefully — don'\''t blindly retry. Check the root cause first.')"
exit 0

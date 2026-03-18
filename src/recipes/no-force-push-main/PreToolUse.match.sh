#!/bin/bash
# Block force push to main/master
source "${HOOKER_HELPERS}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSGS_FILE=".claude/hooker/no-force-push-main.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1 || echo "$2"
}

INPUT=$(cat)
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" != "Bash" ] && exit 1

CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

if echo "$CMD" | grep -q 'git[[:space:]]\+push[[:space:]].*\(-f\|--force\)' && echo "$CMD" | grep -q '\(main\|master\)'; then
    deny "$(yml_get force_push 'Blocked: force push to main/master is not allowed')"
    exit 0
fi

exit 1

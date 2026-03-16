#!/bin/bash
# Block force push to main/master
source "${HOOKER_HELPERS}"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"\K[^"]+' || true)
[ "$TOOL" != "Bash" ] && exit 1

CMD=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"\K[^"]+' || true)

if echo "$CMD" | grep -qP 'git\s+push\s+.*(-f|--force)' && echo "$CMD" | grep -qP '\b(main|master)\b'; then
    deny "Blocked: force push to main/master is not allowed"
    exit 0
fi

exit 1

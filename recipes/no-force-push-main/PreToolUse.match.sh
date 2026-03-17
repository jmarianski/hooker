#!/bin/bash
# Block force push to main/master
source "${HOOKER_HELPERS}"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" != "Bash" ] && exit 1

CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

if echo "$CMD" | grep -q 'git[[:space:]]\+push[[:space:]].*\(-f\|--force\)' && echo "$CMD" | grep -q '\(main\|master\)'; then
    deny "Blocked: force push to main/master is not allowed"
    exit 0
fi

exit 1

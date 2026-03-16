#!/bin/bash
# Block dangerous bash commands
# Adapted from karanb192/claude-code-hooks (MIT)
source "${HOOKER_HELPERS}"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"\K[^"]+' || true)
[ "$TOOL" != "Bash" ] && exit 1

CMD=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"\K[^"]+' || true)
[ -z "$CMD" ] && exit 1

# Dangerous patterns
if echo "$CMD" | grep -qP 'rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+|--force\s+)*(\/|\~|\$HOME|\.\.)'; then
    deny "Blocked: recursive/forced deletion of critical paths"
    exit 0
fi

if echo "$CMD" | grep -qP ':\(\)\{.*\|.*\}|fork\s*bomb'; then
    deny "Blocked: fork bomb detected"
    exit 0
fi

if echo "$CMD" | grep -qP 'curl\s.*\|\s*(ba)?sh|wget\s.*\|\s*(ba)?sh'; then
    deny "Blocked: piping remote script to shell"
    exit 0
fi

if echo "$CMD" | grep -qiP '\b(DROP|TRUNCATE|DELETE\s+FROM)\b.*\b(TABLE|DATABASE)\b'; then
    deny "Blocked: destructive SQL command"
    exit 0
fi

if echo "$CMD" | grep -qP 'mkfs\.|dd\s+if=.*of=/dev/|>\s*/dev/sd'; then
    deny "Blocked: disk/filesystem destruction"
    exit 0
fi

if echo "$CMD" | grep -qP 'chmod\s+(-[a-zA-Z]*\s+)*777\s+/'; then
    deny "Blocked: chmod 777 on root paths"
    exit 0
fi

exit 1

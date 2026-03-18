#!/bin/bash
# Block dangerous bash commands
# Adapted from karanb192/claude-code-hooks (MIT)
source "${HOOKER_HELPERS}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSGS_FILE=".claude/hooker/block-dangerous-commands.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1 || echo "$2"
}

INPUT=$(cat)
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" != "Bash" ] && exit 1

CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$CMD" ] && exit 1

# Dangerous patterns
if echo "$CMD" | grep -q 'rm[[:space:]]\+\(-[a-zA-Z]*f[a-zA-Z]*[[:space:]]\+\|--force[[:space:]]\+\)*\(\/\|\~\|\$HOME\|\.\.\)'; then
    deny "$(yml_get rm_critical 'Blocked: recursive/forced deletion of critical paths')"
    exit 0
fi

if echo "$CMD" | grep -q ':()\{.*|.*\}\|fork[[:space:]]*bomb'; then
    deny "$(yml_get fork_bomb 'Blocked: fork bomb detected')"
    exit 0
fi

if echo "$CMD" | grep -q 'curl[[:space:]].*|[[:space:]]*\(ba\)\{0,1\}sh\|wget[[:space:]].*|[[:space:]]*\(ba\)\{0,1\}sh'; then
    deny "$(yml_get pipe_to_shell 'Blocked: piping remote script to shell')"
    exit 0
fi

if echo "$CMD" | grep -qi '\(DROP\|TRUNCATE\|DELETE[[:space:]]\+FROM\).*\(TABLE\|DATABASE\)'; then
    deny "$(yml_get destructive_sql 'Blocked: destructive SQL command')"
    exit 0
fi

if echo "$CMD" | grep -q 'mkfs\.\|dd[[:space:]]\+if=.*of=/dev/\|>[[:space:]]*/dev/sd'; then
    deny "$(yml_get disk_destroy 'Blocked: disk/filesystem destruction')"
    exit 0
fi

if echo "$CMD" | grep -q 'chmod[[:space:]]\+\(-[a-zA-Z]*[[:space:]]\+\)*777[[:space:]]\+/'; then
    deny "$(yml_get chmod_root 'Blocked: chmod 777 on root paths')"
    exit 0
fi

exit 1

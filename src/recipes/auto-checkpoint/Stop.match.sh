#!/bin/bash
# Auto-commit checkpoint on stop
# Inspired by Scott Chacon's approach (clean-room reimplementation)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSGS_FILE=".claude/hooker/auto-checkpoint.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1 || echo "$2"
}

# Only in git repos
git rev-parse --git-dir &>/dev/null || exit 1

# Only if there are changes
git diff-index --quiet HEAD 2>/dev/null && exit 1

# Stage and commit
git add -A &>/dev/null
git commit -m "$(yml_get commit_msg 'checkpoint: hooker auto-save')" --no-verify &>/dev/null

exit 1

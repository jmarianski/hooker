#!/bin/bash
# Cache Catcher — SessionStart hook
# Marks session as resumed so PostToolUse can skip the first cache miss.
# SessionStart fires on both new sessions and resumes.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

[ -z "$SESSION_ID" ] && exit 0

STATE_DIR="/tmp/cache-catcher"
mkdir -p "$STATE_DIR" 2>/dev/null

# If state file already exists from a previous run, this is a resume
if [ -f "${STATE_DIR}/${SESSION_ID}.state" ]; then
    touch "${STATE_DIR}/${SESSION_ID}.resumed"
fi

# Always mark session as started (for first-run detection)
echo "started: $(date +%s)" > "${STATE_DIR}/${SESSION_ID}.state"

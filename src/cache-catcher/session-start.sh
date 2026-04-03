#!/bin/bash
# Cache Catcher — SessionStart hook
# Marks session as resumed with gap duration so PostToolUse knows whether
# to skip the first cache miss (>1h gap = expected rebuild) or flag it (<1h = bad).
# SessionStart fires on both new sessions and resumes.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

[ -z "$SESSION_ID" ] && exit 0

STATE_DIR="/tmp/cache-catcher"
mkdir -p "$STATE_DIR" 2>/dev/null
LOG="${STATE_DIR}/debug.log"
STATE_FILE="${STATE_DIR}/${SESSION_ID}.session"
RESUME_FILE="${STATE_DIR}/${SESSION_ID}.resumed"
NOW=$(date +%s 2>/dev/null || echo 0)

log() { echo "[$(date '+%H:%M:%S')] [session-start] $*" >> "$LOG"; }

log "SessionStart fired. session=${SESSION_ID}"

# If state file exists, this is a resume — calculate gap
if [ -f "$STATE_FILE" ]; then
    LAST_ACTIVE=$(sed -n 's/^last_active:[[:space:]]*//p' "$STATE_FILE" 2>/dev/null | head -1)
    LAST_ACTIVE="${LAST_ACTIVE:-0}"
    GAP=$((NOW - LAST_ACTIVE))
    log "Resume detected. last_active=${LAST_ACTIVE} now=${NOW} gap=${GAP}s"

    if [ "$GAP" -gt 3600 ] 2>/dev/null; then
        echo "long" > "$RESUME_FILE"
        log "Long resume (>1h). Wrote 'long' to ${RESUME_FILE}"
    else
        rm -f "$RESUME_FILE" 2>/dev/null
        log "Short resume (<1h). No skip marker."
    fi
else
    log "First start (no session file). Creating ${STATE_FILE}"
fi

# Update last active timestamp (separate file from match.sh's .state)
echo "last_active: ${NOW}" > "$STATE_FILE"
log "Updated last_active=${NOW}"

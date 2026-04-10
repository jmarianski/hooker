#!/bin/bash
# Ralph Wiggum — SessionStart hook
# Detects RALPH_START in prompt, loads previous iteration state
source "${HOOKER_HELPERS}"

INPUT=$(cat)
PROJECT_DIR="${HOOKER_CWD:-.}"
STATE_FILE="${PROJECT_DIR}/.claude/ralph-state.json"

# Check for RALPH_START marker (set by outer loop / skill)
SESSION_ID=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Also check env var (outer loop can set RALPH_ITERATION)
if [ -z "${RALPH_START:-}" ] && [ -z "${RALPH_ITERATION:-}" ]; then
    # No explicit marker - check if we have state file from recent session
    # This handles the case where user just runs `claude -p "continue ralph"`
    [ -f "$STATE_FILE" ] || exit 1

    # State exists but check if it's a fresh continuation request
    LAST_UPDATE=$(stat -c %Y "$STATE_FILE" 2>/dev/null || stat -f %m "$STATE_FILE" 2>/dev/null)
    NOW=$(date +%s)
    AGE=$((NOW - LAST_UPDATE))

    # If state is older than 1 hour, don't auto-activate
    [ "$AGE" -gt 3600 ] && exit 1
fi

# Load state
ITERATION="${RALPH_ITERATION:-1}"
TASK="${RALPH_TASK:-}"
SUMMARY=""

if [ -f "$STATE_FILE" ]; then
    PREV_ITER=$(sed -n 's/.*"iteration"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$STATE_FILE" | tail -1)
    SUMMARY=$(sed -n 's/.*"summary"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" | tail -1)
    TASK=$(sed -n 's/.*"task"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" | tail -1)
    COMPLETED=$(sed -n 's/.*"completed"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$STATE_FILE" | tail -1)

    if [ "$COMPLETED" = "true" ]; then
        inject "Ralph Wiggum: Previous run marked COMPLETE. Starting fresh or verifying completion."
        exit 0
    fi

    # If no explicit iteration, increment from state
    [ -z "${RALPH_ITERATION:-}" ] && ITERATION=$((PREV_ITER + 1))
fi

# Build context injection
if [ -n "$SUMMARY" ]; then
    MSG="RALPH WIGGUM MODE — Iteration ${ITERATION}

Previous iteration summary:
${SUMMARY}

Continue the task. When FULLY complete, output exactly: RALPH_DONE
Do not output RALPH_DONE until everything is verified working."
else
    MSG="RALPH WIGGUM MODE — Iteration ${ITERATION}

Task: ${TASK:-Continue working on the assigned task.}

When FULLY complete, output exactly: RALPH_DONE
Do not output RALPH_DONE until everything is verified working."
fi

inject "$MSG"
exit 0

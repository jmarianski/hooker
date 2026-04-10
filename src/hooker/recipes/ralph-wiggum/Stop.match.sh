#!/bin/bash
# Ralph Wiggum — Stop hook
# Asks deterministically if task is done, saves state for next iteration
source "${HOOKER_HELPERS}"

INPUT=$(cat)
PROJECT_DIR="${HOOKER_CWD:-.}"
STATE_FILE="${PROJECT_DIR}/.claude/ralph-state.json"
TRANSCRIPT="${HOOKER_TRANSCRIPT:-}"

# Only act if Ralph state exists (means we're in Ralph mode)
[ -f "$STATE_FILE" ] || [ -n "${RALPH_ITERATION:-}" ] || exit 1

# Avoid loop - check if stop hook already active
if echo "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    exit 0
fi

# Get current iteration from state or env
ITERATION="${RALPH_ITERATION:-1}"
if [ -f "$STATE_FILE" ]; then
    STATE_ITER=$(sed -n 's/.*"iteration"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$STATE_FILE" | tail -1)
    [ -n "$STATE_ITER" ] && ITERATION="$STATE_ITER"
fi

# Check if RALPH_DONE already in transcript
COMPLETED="false"
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    if grep -q "RALPH_DONE" "$TRANSCRIPT" 2>/dev/null; then
        COMPLETED="true"
    fi
fi

# If already done, just save and exit
if [ "$COMPLETED" = "true" ]; then
    TASK=$(sed -n 's/.*"task"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" 2>/dev/null | tail -1)
    cat > "$STATE_FILE" << EOF
{
  "iteration": ${ITERATION},
  "completed": true,
  "task": "${TASK:-}",
  "summary": "Task completed (RALPH_DONE)",
  "timestamp": "$(date -Iseconds)"
}
EOF
    exit 0
fi

# Not done yet - ask deterministically and save summary
remind "RALPH WIGGUM — Iteration ${ITERATION} ending.

Is the task COMPLETELY done and verified working?

If YES: Write single word RALPH_DONE (nothing else)
If NO: Write a 2-3 sentence summary of progress and what remains.

Do NOT continue working on the task. Just answer the question above."

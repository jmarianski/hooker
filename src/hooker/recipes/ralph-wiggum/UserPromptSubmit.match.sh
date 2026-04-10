#!/bin/bash
# Ralph Wiggum — UserPromptSubmit hook
# Captures summary response after Stop hook's question
# Also detects manual "continue ralph" requests
source "${HOOKER_HELPERS}"

INPUT=$(cat)
PROJECT_DIR="${HOOKER_CWD:-.}"
STATE_FILE="${PROJECT_DIR}/.claude/ralph-state.json"

# Only act if Ralph state exists
[ -f "$STATE_FILE" ] || exit 1

# Get user prompt content
USER_PROMPT=$(echo "$INPUT" | sed -n 's/.*"user_prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$USER_PROMPT" ] && USER_PROMPT=$(echo "$INPUT" | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Check if this is RALPH_DONE response
if echo "$USER_PROMPT" | grep -q "^RALPH_DONE$\|^RALPH_DONE[[:space:]]*$"; then
    # Mark as completed
    ITERATION=$(sed -n 's/.*"iteration"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$STATE_FILE" | tail -1)
    TASK=$(sed -n 's/.*"task"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" | tail -1)
    cat > "$STATE_FILE" << EOF
{
  "iteration": ${ITERATION:-1},
  "completed": true,
  "task": "${TASK:-}",
  "summary": "Task completed",
  "timestamp": "$(date -Iseconds)"
}
EOF
    inject "Ralph Wiggum: Task marked COMPLETE."
    exit 0
fi

# Check if this looks like a summary (response to Stop hook question)
# Heuristic: short-ish text that's not a new task request
PROMPT_LEN=${#USER_PROMPT}
if [ "$PROMPT_LEN" -gt 10 ] && [ "$PROMPT_LEN" -lt 1000 ]; then
    # Looks like a summary - save it
    ITERATION=$(sed -n 's/.*"iteration"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$STATE_FILE" | tail -1)
    TASK=$(sed -n 's/.*"task"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" | tail -1)

    # Escape for JSON
    SUMMARY=$(echo "$USER_PROMPT" | tr '\n' ' ' | sed 's/"/\\"/g' | cut -c1-500)

    cat > "$STATE_FILE" << EOF
{
  "iteration": ${ITERATION:-1},
  "completed": false,
  "task": "${TASK:-}",
  "summary": "${SUMMARY}",
  "timestamp": "$(date -Iseconds)"
}
EOF
fi

exit 1  # Don't inject anything, just saved state

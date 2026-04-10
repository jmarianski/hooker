#!/bin/bash
# Ralph Wiggum — Stop hook (standalone)
# Activates ONLY when RALPH_ITERATION env var is set
# Checks transcript for completion, asks for summary if not done

# Only activate if in Ralph mode
[ -z "${RALPH_ITERATION:-}" ] && exit 0

INPUT=$(cat)

# Extract fields from hook JSON
CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
TRANSCRIPT=$(echo "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
PROJECT_DIR="${CWD:-$(pwd)}"
STATE_FILE="${PROJECT_DIR}/.claude/ralph-state.json"
MARKER="${RALPH_COMPLETION_MARKER:-RALPH_DONE}"
ITERATION="${RALPH_ITERATION}"

# Avoid infinite loop - check if stop hook already active
if echo "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    exit 0
fi

# Check if completion marker already in transcript
COMPLETED="false"
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    if grep -q "$MARKER" "$TRANSCRIPT" 2>/dev/null; then
        COMPLETED="true"
    fi
fi

# Get task from env or state
TASK="${RALPH_TASK:-}"
[ -z "$TASK" ] && [ -f "$STATE_FILE" ] && \
    TASK=$(sed -n 's/.*"task"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" | tail -1)

# If already done, save state and exit quietly
if [ "$COMPLETED" = "true" ]; then
    mkdir -p "$(dirname "$STATE_FILE")"
    cat > "$STATE_FILE" << EOF
{
  "iteration": ${ITERATION},
  "completed": true,
  "task": "${TASK:-}",
  "summary": "Task completed (${MARKER})",
  "timestamp": "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
}
EOF
    exit 0  # Don't block, outer loop will see completed state
fi

# Not done - remind (block) asking for summary
MSG="RALPH WIGGUM — Iteration ${ITERATION} ending.

Is the task COMPLETELY done and verified working?

If YES: Write exactly: ${MARKER}
If NO: Write a 2-3 sentence summary of progress and what remains.

Do NOT continue working. Just answer above."

ESCAPED=$(printf '%s' "$MSG" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
echo "{\"decision\": \"block\", \"reason\": \"${ESCAPED}\"}"

#!/bin/bash
# Ralph Wiggum — SessionStart hook (standalone)
# Activates ONLY when RALPH_ITERATION env var is set by outer loop
# Loads previous iteration state and injects context

# Only activate if outer loop set RALPH_ITERATION
[ -z "${RALPH_ITERATION:-}" ] && exit 0

INPUT=$(cat)

# Extract cwd from hook JSON
CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
PROJECT_DIR="${CWD:-$(pwd)}"
STATE_FILE="${PROJECT_DIR}/.claude/ralph-state.json"

ITERATION="${RALPH_ITERATION}"
TASK="${RALPH_TASK:-}"
SUMMARY=""
MARKER="${RALPH_COMPLETION_MARKER:-RALPH_DONE}"

# Load state from previous iteration
if [ -f "$STATE_FILE" ]; then
    SUMMARY=$(sed -n 's/.*"summary"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" | tail -1)
    [ -z "$TASK" ] && TASK=$(sed -n 's/.*"task"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" | tail -1)
    COMPLETED=$(sed -n 's/.*"completed"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$STATE_FILE" | tail -1)

    if [ "$COMPLETED" = "true" ]; then
        echo '{"systemMessage": "Ralph Wiggum: Previous task marked COMPLETE."}'
        exit 0
    fi
fi

# JSON escape helper
_escape() {
    printf '%s' "$1" | awk '{
        gsub(/\\/, "\\\\")
        gsub(/"/, "\\\"")
        gsub(/\t/, "\\t")
        gsub(/\r/, "\\r")
        gsub(/\n/, "\\n")
        printf "%s", $0
    }'
}

# Build context injection
if [ -n "$SUMMARY" ]; then
    MSG="RALPH WIGGUM — Iteration ${ITERATION}

Previous iteration summary:
${SUMMARY}

Continue the task. When FULLY complete, output exactly: ${MARKER}
Do not output ${MARKER} until everything is verified working."
else
    MSG="RALPH WIGGUM — Iteration ${ITERATION}

Task: ${TASK:-Continue working on the assigned task.}

When FULLY complete, output exactly: ${MARKER}
Do not output ${MARKER} until everything is verified working."
fi

# Output with escaped newlines
ESCAPED=$(printf '%s' "$MSG" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
echo "{\"systemMessage\": \"${ESCAPED}\"}"

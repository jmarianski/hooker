#!/bin/bash
# Ralph Wiggum — UserPromptSubmit hook
# 1. CLI intercept: "ralph <cmd>" in prompt → run ralph.sh
# 2. State capture: save summary after Stop hook question (when in Ralph mode)

INPUT=$(cat)

# Extract prompt
PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
PROJECT_DIR="${CWD:-$(pwd)}"
STATE_FILE="${PROJECT_DIR}/.claude/ralph-state.json"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# JSON escape helper
_json_escape() {
    awk '{
        gsub(/\\/, "\\\\")
        gsub(/"/, "\\\"")
        gsub(/\t/, "\\t")
        gsub(/\r/, "\\r")
        printf "%s", (NR>1 ? "\\n" : "") $0
    }'
}

# =========================================================
# 1. CLI COMMAND INTERCEPT
# =========================================================
case "$PROMPT" in
    ralph|ralph\ *)
        # Extract command after "ralph "
        if [ "$PROMPT" = "ralph" ]; then
            CMD=""
        else
            CMD="${PROMPT#ralph }"
        fi

        CLI="${SCRIPT_DIR}/scripts/ralph.sh"

        # Run CLI, capture output (strip ANSI for clean block message)
        ESC=$(printf '\033')
        OUTPUT=$(bash "$CLI" $CMD 2>&1 | sed "s/${ESC}\[[0-9;]*m//g")

        if [ -z "$OUTPUT" ]; then
            OUTPUT="ralph: no output for '$CMD'"
        fi

        # Block prompt — show output to user
        ESCAPED=$(printf '%s' "$OUTPUT" | _json_escape)
        echo "{\"decision\": \"block\", \"reason\": \"${ESCAPED}\"}"
        exit 0
        ;;
esac

# =========================================================
# 2. STATE CAPTURE (when in Ralph mode via env var)
# =========================================================
[ -z "${RALPH_ITERATION:-}" ] && exit 0

MARKER="${RALPH_COMPLETION_MARKER:-RALPH_DONE}"
ITERATION="${RALPH_ITERATION}"

# Get task from env or state
TASK="${RALPH_TASK:-}"
[ -z "$TASK" ] && [ -f "$STATE_FILE" ] && \
    TASK=$(sed -n 's/.*"task"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" | tail -1)

# Check if this is completion marker
if echo "$PROMPT" | grep -qE "^${MARKER}[[:space:]]*$"; then
    mkdir -p "$(dirname "$STATE_FILE")"
    cat > "$STATE_FILE" << EOF
{
  "iteration": ${ITERATION},
  "completed": true,
  "task": "${TASK:-}",
  "summary": "Task completed",
  "timestamp": "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
}
EOF
    ESCAPED=$(printf '%s' "Ralph Wiggum: Task marked COMPLETE." | _json_escape)
    echo "{\"systemMessage\": \"${ESCAPED}\"}"
    exit 0
fi

# Check if this looks like a summary (10-500 chars)
PROMPT_LEN=${#PROMPT}
if [ "$PROMPT_LEN" -gt 10 ] && [ "$PROMPT_LEN" -lt 500 ]; then
    # Escape for JSON
    SUMMARY=$(printf '%s' "$PROMPT" | tr '\n' ' ' | sed 's/"/\\"/g' | cut -c1-500)

    mkdir -p "$(dirname "$STATE_FILE")"
    cat > "$STATE_FILE" << EOF
{
  "iteration": ${ITERATION},
  "completed": false,
  "task": "${TASK:-}",
  "summary": "${SUMMARY}",
  "timestamp": "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
}
EOF
fi

exit 0

#!/bin/bash
# Ralph Wiggum — CLI outer loop
# Runs multiple Claude iterations with fresh context each time
# Usage: ralph [options] "task description"

set -e

# Defaults
MAX_ITERATIONS=10
TIMEOUT=300
MARKER="RALPH_DONE"
STATE_FILE=".claude/ralph-state.json"
PAUSE=2

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

usage() {
    echo -e "${BOLD}ralph${NC} — autonomous multi-iteration Claude execution"
    echo ""
    echo -e "${BOLD}Usage:${NC} ralph [options] <task description>"
    echo -e "       ralph status"
    echo -e "       ralph clear"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  <task>     Start new task (or continue existing)"
    echo "  status     Show current state"
    echo "  clear      Clear state file"
    echo "  help       Show this help"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  -n, --max-iterations N   Max iterations (default: 10, 0=unlimited)"
    echo "  -t, --timeout SECONDS    Timeout per iteration (default: 300)"
    echo "  -m, --marker STRING      Completion marker (default: RALPH_DONE)"
    echo "  -c, --continue           Continue existing task (don't reset)"
    echo ""
    echo -e "${BOLD}Environment:${NC}"
    echo "  RALPH_ITERATION          Current iteration (set by this script)"
    echo "  RALPH_TASK               Task description"
    echo "  RALPH_COMPLETION_MARKER  Completion marker"
    echo ""
    echo -e "${BOLD}State:${NC} ${STATE_FILE}"
}

cmd_status() {
    if [ ! -f "$STATE_FILE" ]; then
        echo -e "${YELLOW}No Ralph state found${NC}"
        exit 0
    fi
    echo -e "${BOLD}Ralph Wiggum State${NC}"
    echo ""
    cat "$STATE_FILE" | while IFS= read -r line; do
        echo "  $line"
    done
}

cmd_clear() {
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
        echo -e "${GREEN}State cleared${NC}"
    else
        echo -e "${YELLOW}No state to clear${NC}"
    fi
}

# Parse args
CONTINUE=0
TASK=""
while [ $# -gt 0 ]; do
    case "$1" in
        -n|--max-iterations) MAX_ITERATIONS="$2"; shift ;;
        -t|--timeout) TIMEOUT="$2"; shift ;;
        -m|--marker) MARKER="$2"; shift ;;
        -c|--continue) CONTINUE=1 ;;
        -h|--help|help) usage; exit 0 ;;
        status) cmd_status; exit 0 ;;
        clear) cmd_clear; exit 0 ;;
        *)
            if [ -z "$TASK" ]; then
                TASK="$1"
            else
                TASK="$TASK $1"
            fi
            ;;
    esac
    shift
done

if [ -z "$TASK" ] && [ "$CONTINUE" -eq 0 ]; then
    # Check if we have existing state to continue
    if [ -f "$STATE_FILE" ]; then
        COMPLETED=$(sed -n 's/.*"completed"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$STATE_FILE" | tail -1)
        if [ "$COMPLETED" != "true" ]; then
            TASK=$(sed -n 's/.*"task"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" | tail -1)
            CONTINUE=1
            echo -e "${CYAN}Continuing existing task:${NC} $TASK"
        fi
    fi
fi

if [ -z "$TASK" ]; then
    echo -e "${RED}Error: No task specified${NC}" >&2
    echo "Usage: ralph \"your task description\"" >&2
    exit 1
fi

# Initialize state if not continuing
START_ITER=1
if [ "$CONTINUE" -eq 1 ] && [ -f "$STATE_FILE" ]; then
    PREV_ITER=$(sed -n 's/.*"iteration"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$STATE_FILE" | tail -1)
    [ -n "$PREV_ITER" ] && START_ITER=$((PREV_ITER + 1))
else
    mkdir -p "$(dirname "$STATE_FILE")"
    cat > "$STATE_FILE" << EOF
{
  "iteration": 0,
  "completed": false,
  "task": "$(echo "$TASK" | sed 's/"/\\"/g')",
  "summary": "",
  "timestamp": "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
}
EOF
fi

echo -e "${BOLD}Ralph Wiggum${NC} — Starting task execution"
echo -e "${DIM}Task:${NC} $TASK"
echo -e "${DIM}Max iterations:${NC} $MAX_ITERATIONS"
echo -e "${DIM}Timeout:${NC} ${TIMEOUT}s"
echo ""

# Main loop
i=$START_ITER
while true; do
    # Check max iterations
    if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$i" -gt "$MAX_ITERATIONS" ]; then
        echo -e "${YELLOW}Max iterations ($MAX_ITERATIONS) reached${NC}"
        break
    fi

    echo -e "${CYAN}═══ Iteration $i ═══${NC}"

    # Run Claude with env vars
    OUTPUT=$(RALPH_ITERATION=$i \
             RALPH_TASK="$TASK" \
             RALPH_COMPLETION_MARKER="$MARKER" \
             timeout "$TIMEOUT" claude -p "$TASK" 2>&1) || true

    echo "$OUTPUT"

    # Check for completion marker in output
    if echo "$OUTPUT" | grep -q "$MARKER"; then
        echo ""
        echo -e "${GREEN}✓ Task completed (${MARKER} found)${NC}"
        break
    fi

    # Check state file
    if [ -f "$STATE_FILE" ]; then
        COMPLETED=$(sed -n 's/.*"completed"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$STATE_FILE" | tail -1)
        if [ "$COMPLETED" = "true" ]; then
            echo ""
            echo -e "${GREEN}✓ Task marked complete in state${NC}"
            break
        fi
    fi

    # Pause before next iteration
    echo -e "${DIM}Pausing ${PAUSE}s before next iteration...${NC}"
    sleep "$PAUSE"

    i=$((i + 1))
done

echo ""
echo -e "${BOLD}Final state:${NC}"
cmd_status

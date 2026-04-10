#!/bin/bash
# Ralph Wiggum — Autonomous iteration loop wrapper
# Spawns fresh claude -p sessions with state continuity via hooks
#
# Usage: ralph.sh [OPTIONS] "task description"
#        ralph.sh [OPTIONS] -f task-file.md
#
# Options:
#   -n, --max-iterations N    Maximum iterations (default: 10, 0=unlimited)
#   -t, --timeout SECONDS     Timeout per iteration (default: 300, 0=none)
#   -m, --marker STRING       Completion marker (default: RALPH_DONE)
#   -f, --file FILE           Read task from file instead of argument
#   -c, --config FILE         Custom config file
#   -v, --verbose             Verbose output
#   -h, --help                Show help
#
# Based on ghuntley.com/ralph concept:
# - Each iteration = fresh context (no context rot)
# - Hooks provide memory between iterations via state file
# - Loop continues until completion marker or max iterations

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Defaults
MAX_ITERATIONS=10
TIMEOUT=300
COMPLETION_MARKER="RALPH_DONE"
TASK=""
TASK_FILE=""
CONFIG_FILE=""
VERBOSE=false
STATE_FILE=".claude/ralph-state.json"
LOG_FILE=".claude/ralph-history.log"
PAUSE=2

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--max-iterations)
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -m|--marker)
            COMPLETION_MARKER="$2"
            shift 2
            ;;
        -f|--file)
            TASK_FILE="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Ralph Wiggum — Autonomous iteration loop"
            echo ""
            echo "Usage: ralph.sh [OPTIONS] \"task description\""
            echo "       ralph.sh [OPTIONS] -f task-file.md"
            echo ""
            echo "Options:"
            echo "  -n, --max-iterations N    Maximum iterations (default: 10)"
            echo "  -t, --timeout SECONDS     Timeout per iteration (default: 300)"
            echo "  -m, --marker STRING       Completion marker (default: RALPH_DONE)"
            echo "  -f, --file FILE           Read task from file"
            echo "  -c, --config FILE         Custom config file"
            echo "  -v, --verbose             Verbose output"
            echo "  -h, --help                Show help"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            TASK="$1"
            shift
            ;;
    esac
done

# Load config if provided
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    [ "$VERBOSE" = true ] && echo "Loading config: $CONFIG_FILE"
    MAX_ITERATIONS=$(sed -n 's/^max_iterations:[[:space:]]*\([0-9]*\)/\1/p' "$CONFIG_FILE" | head -1)
    TIMEOUT=$(sed -n 's/^timeout_per_iteration:[[:space:]]*\([0-9]*\)/\1/p' "$CONFIG_FILE" | head -1)
    COMPLETION_MARKER=$(sed -n 's/^completion_marker:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}/\1/p' "$CONFIG_FILE" | head -1)
    STATE_FILE=$(sed -n 's/^state_file:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}/\1/p' "$CONFIG_FILE" | head -1)
    LOG_FILE=$(sed -n 's/^log_file:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}/\1/p' "$CONFIG_FILE" | head -1)
    PAUSE=$(sed -n 's/^pause_between_iterations:[[:space:]]*\([0-9]*\)/\1/p' "$CONFIG_FILE" | head -1)
fi

# Set defaults if not set
MAX_ITERATIONS="${MAX_ITERATIONS:-10}"
TIMEOUT="${TIMEOUT:-300}"
COMPLETION_MARKER="${COMPLETION_MARKER:-RALPH_DONE}"
STATE_FILE="${STATE_FILE:-.claude/ralph-state.json}"
LOG_FILE="${LOG_FILE:-.claude/ralph-history.log}"
PAUSE="${PAUSE:-2}"

# Get task from file if specified
if [ -n "$TASK_FILE" ]; then
    [ -f "$TASK_FILE" ] || { echo "Task file not found: $TASK_FILE" >&2; exit 1; }
    TASK=$(cat "$TASK_FILE")
fi

# Validate task
[ -z "$TASK" ] && { echo "No task provided. Use: ralph.sh \"task\" or ralph.sh -f file.md" >&2; exit 1; }

# Ensure directories exist
mkdir -p "$(dirname "$STATE_FILE")" "$(dirname "$LOG_FILE")"

# Initialize state
echo '{"iteration": 0, "completed": false, "summary": "", "timestamp": ""}' > "$STATE_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    [ "$VERBOSE" = true ] && echo "$*"
}

log "Starting Ralph Wiggum loop"
log "Task: $TASK"
log "Max iterations: $MAX_ITERATIONS"
log "Timeout: ${TIMEOUT}s"
log "Completion marker: $COMPLETION_MARKER"

ITERATION=0
COMPLETED=false

while true; do
    ITERATION=$((ITERATION + 1))

    # Check max iterations
    if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATION" -gt "$MAX_ITERATIONS" ]; then
        log "Maximum iterations ($MAX_ITERATIONS) reached"
        echo "Maximum iterations reached. Check $STATE_FILE for progress."
        break
    fi

    log "=== Iteration $ITERATION ==="

    # Build prompt
    if [ "$ITERATION" -eq 1 ]; then
        PROMPT="$TASK

When the task is fully complete, output exactly: $COMPLETION_MARKER"
    else
        # Load previous summary
        SUMMARY=$(sed -n 's/.*"summary"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" | tail -1)
        PROMPT="Continue the task from iteration $((ITERATION - 1)).

Previous progress:
$SUMMARY

Continue where you left off. When fully complete, output exactly: $COMPLETION_MARKER"
    fi

    # Export env vars for hooks
    export RALPH_ITERATION="$ITERATION"
    export RALPH_TASK="$TASK"
    export RALPH_MAX_ITERATIONS="$MAX_ITERATIONS"
    export RALPH_COMPLETION_MARKER="$COMPLETION_MARKER"

    # Run claude with timeout
    log "Spawning claude -p session..."
    CLAUDE_OUTPUT=""
    if [ "$TIMEOUT" -gt 0 ]; then
        CLAUDE_OUTPUT=$(timeout "${TIMEOUT}s" claude -p "$PROMPT" 2>&1) || {
            EXIT_CODE=$?
            if [ "$EXIT_CODE" -eq 124 ]; then
                log "Iteration timed out after ${TIMEOUT}s"
            else
                log "Claude exited with code $EXIT_CODE"
            fi
        }
    else
        CLAUDE_OUTPUT=$(claude -p "$PROMPT" 2>&1) || log "Claude exited with non-zero"
    fi

    # Check for completion marker in output
    if echo "$CLAUDE_OUTPUT" | grep -q "$COMPLETION_MARKER"; then
        log "Completion marker found!"
        COMPLETED=true
        # Update state
        cat > "$STATE_FILE" << EOF
{
  "iteration": $ITERATION,
  "completed": true,
  "summary": "Task completed",
  "timestamp": "$(date -Iseconds)"
}
EOF
        echo "Task completed after $ITERATION iteration(s)."
        break
    fi

    # Check state file (updated by Stop hook)
    if [ -f "$STATE_FILE" ]; then
        STATE_COMPLETED=$(sed -n 's/.*"completed"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$STATE_FILE" | tail -1)
        if [ "$STATE_COMPLETED" = "true" ]; then
            log "State file indicates completion"
            COMPLETED=true
            echo "Task completed after $ITERATION iteration(s)."
            break
        fi
    fi

    log "Iteration $ITERATION complete, pausing ${PAUSE}s before next..."
    sleep "$PAUSE"
done

# Cleanup env vars
unset RALPH_ITERATION RALPH_TASK RALPH_MAX_ITERATIONS RALPH_COMPLETION_MARKER

log "Ralph Wiggum loop finished. Completed: $COMPLETED, Iterations: $ITERATION"
echo ""
echo "Summary:"
echo "  Iterations: $ITERATION"
echo "  Completed: $COMPLETED"
echo "  State file: $STATE_FILE"
echo "  Log file: $LOG_FILE"

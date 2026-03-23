#!/bin/bash
# Cron Results Notifier — save session summary for later review
# SessionEnd hook: fires when a session ends
# In cron/headless mode, saves a summary to cron-results dir.
# In interactive mode, cleans up .cron-notified marker.
source "${HOOKER_HELPERS}"

INPUT=$(cat)

RESULTS_DIR=".claude/hooker/cron-results"
NOTIFIED_MARKER=".claude/hooker/.cron-notified"

# Clean up notified marker on session end (so next session checks again)
rm -f "$NOTIFIED_MARKER" 2>/dev/null

# Detect headless/cron mode: no TTY on stdin
if [ -t 0 ] 2>/dev/null; then
    # Interactive session — nothing to save
    exit 1
fi

# Headless/cron session — save a result file
# The actual content should be provided by the cron prompt itself
# This hook creates the results directory and a placeholder
mkdir -p "$RESULTS_DIR"

TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
RESULT_FILE="${RESULTS_DIR}/session-${TIMESTAMP}.md"

# Check transcript for what was done
TRANSCRIPT=$(echo "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    # Extract last assistant messages as summary
    SUMMARY=$(tail -50 "$TRANSCRIPT" | grep '"type":"assistant"' | tail -5 | sed -n 's/.*"text":"\([^"]*\)".*/\1/p' | head -5)
    if [ -n "$SUMMARY" ]; then
        cat > "$RESULT_FILE" << EOF
# Cron Session Results — $(date '+%Y-%m-%d %H:%M')

$SUMMARY
EOF
        inject "Session results saved to ${RESULT_FILE}."
        exit 0
    fi
fi

exit 1

#!/bin/bash
# Re-inject context after compaction
# Only fires on compact/resume, not fresh starts
source "${HOOKER_HELPERS}"

INPUT=$(cat)
SOURCE=$(echo "$INPUT" | grep -oP '"source"\s*:\s*"\K[^"]+' || true)

# Only fire after compaction or resume (context was likely lost)
case "$SOURCE" in
    compact|resume) ;;
    *) exit 1 ;;
esac

# Load project-specific context file if it exists
CONTEXT_FILE=".claude/hooker/context.md"
[ -f "$CONTEXT_FILE" ] || exit 1

inject "$(cat "$CONTEXT_FILE")"
exit 0

#!/bin/bash
# Remind about docs/tests — block stop if last turn had file edits
set -euo pipefail

INPUT=$(cat)

# Prevent infinite loop
echo "$INPUT" | grep -qP '"stop_hook_active"\s*:\s*true' && exit 1

# Check transcript for file modifications in last assistant turn
TRANSCRIPT=$(echo "$INPUT" | grep -oP '"transcript_path"\s*:\s*"\K[^"]+' || true)
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 1

# Check for Edit/Write in last assistant turn only (since last user message)
LAST_TURN=$(tac "$TRANSCRIPT" | sed -n '1,/"type"\s*:\s*"user"/p' 2>/dev/null) || true
echo "$LAST_TURN" | grep -qP '"name"\s*:\s*"(Edit|Write|NotebookEdit)"' || exit 1

echo '{"decision": "block", "reason": "Hooker reminder: Did you update docs, tests, and clean up TODOs?"}'
exit 0

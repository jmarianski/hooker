#!/bin/bash
# Remind about docs/tests — fires only if files were modified
set -euo pipefail

INPUT=$(cat)

# Prevent infinite loop
echo "$INPUT" | grep -qP '"stop_hook_active"\s*:\s*true' && exit 1

# Check transcript for file modifications
TRANSCRIPT=$(echo "$INPUT" | grep -oP '"transcript_path"\s*:\s*"\K[^"]+' || true)
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 1
grep -qP '"name"\s*:\s*"(Edit|Write|NotebookEdit)"' "$TRANSCRIPT" 2>/dev/null || exit 1

# Block stop with visible reminder
cat <<'EOF'
{"decision": "block", "reason": "Hooker reminder: Did you update docs, tests, and clean up TODOs?"}
EOF
exit 0

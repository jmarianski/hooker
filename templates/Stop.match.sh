#!/bin/bash
# Match: fire only if files were modified (Edit, Write, or NotebookEdit used)
# Receives hook input JSON on stdin, checks transcript for tool uses.

set -euo pipefail

INPUT=$(cat)

# Extract transcript path from input JSON
TRANSCRIPT=$(echo "$INPUT" | grep -oP '"transcript_path"\s*:\s*"\K[^"]+' || true)

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    exit 1
fi

# Check if any file-modifying tools were used in this session
grep -qP '"tool_name"\s*:\s*"(Edit|Write|NotebookEdit)"' "$TRANSCRIPT" 2>/dev/null

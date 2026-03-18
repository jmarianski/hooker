#!/bin/bash
# Inject CLAUDE.md + MEMORY.md into every subagent's context
# Standalone match script (no .md template needed)
set -euo pipefail

CWD="${HOOKER_CWD:-.}"

# Project instructions
CLAUDE_MD="${CWD}/CLAUDE.md"

# Memory index — auto-detect from CWD
PROJECT_SLUG=$(echo "$CWD" | sed 's|/|-|g; s|^-||')
MEMORY_MD="${HOME}/.claude/projects/-${PROJECT_SLUG}/memory/MEMORY.md"

OUTPUT=""

if [ -f "$CLAUDE_MD" ]; then
    OUTPUT+="# Project Instructions (CLAUDE.md)
$(cat "$CLAUDE_MD")
"
fi

if [ -f "$MEMORY_MD" ]; then
    OUTPUT+="
---
# Memory (MEMORY.md)
$(cat "$MEMORY_MD")
"
fi

if [ -n "$OUTPUT" ]; then
    echo "$OUTPUT"
    exit 0
fi

exit 1

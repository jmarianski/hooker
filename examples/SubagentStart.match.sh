#!/bin/bash
# Inject CLAUDE.md + MEMORY.md into every subagent's context
# Standalone match script (no .md template needed)
#
# Usage: copy to .claude/hooker/SubagentStart.match.sh and chmod +x
# The script reads project instructions and memory, then injects them
# so subagents have the same context as the main session.

set -euo pipefail

CWD="${HOOKER_CWD:-.}"

# Project instructions
CLAUDE_MD="${CWD}/CLAUDE.md"

# Memory index — adjust path to match your project
# Find yours with: ls ~/.claude/projects/*/memory/MEMORY.md
MEMORY_MD="${HOME}/.claude/projects/YOUR_PROJECT_PATH/memory/MEMORY.md"

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

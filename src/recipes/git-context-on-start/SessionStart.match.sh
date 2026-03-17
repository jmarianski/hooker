#!/bin/bash
# Inject git context on session start
source "${HOOKER_HELPERS}"

git rev-parse --git-dir &>/dev/null || exit 1

BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
STATUS=$(git status --short 2>/dev/null | head -15)
RECENT=$(git log --oneline -5 2>/dev/null)

OUTPUT="## Git Context
Branch: ${BRANCH}
"

[ -n "$STATUS" ] && OUTPUT+="
### Uncommitted changes
${STATUS}
"

[ -n "$RECENT" ] && OUTPUT+="
### Recent commits
${RECENT}
"

inject "$OUTPUT"
exit 0

#!/bin/bash
# Inject AGENTS.md into session context
# Walks up from CWD to find nearest AGENTS.md
source "${HOOKER_HELPERS}"

find_agents_md() {
    local DIR="$(pwd)"
    while [ "$DIR" != "/" ]; do
        [ -f "${DIR}/AGENTS.md" ] && echo "${DIR}/AGENTS.md" && return
        DIR=$(dirname "$DIR")
    done
    return 1
}

AGENTS_FILE=$(find_agents_md) || exit 1
CONTENT=$(cat "$AGENTS_FILE" 2>/dev/null)
[ -z "$CONTENT" ] && exit 1

inject "$CONTENT"
exit 0

#!/bin/bash
# Hooker setup-cron — install/update crontab entries from schedules.yml
# Reads .claude/hooker/schedules.yml, generates crontab entries with
# claude -p, replaces existing entries for this project directory.
#
# Usage: bash setup-cron.sh [path/to/schedules.yml]
# Run from project root or pass config path.

set -euo pipefail

CONFIG="${1:-.claude/hooker/schedules.yml}"
PROJECT_DIR="$(pwd)"

if [ ! -f "$CONFIG" ]; then
    echo "No schedules.yml found at $CONFIG"
    echo "Create one with:"
    echo ""
    echo "schedules:"
    echo "  - name: nightly-review"
    echo "    cron: \"0 3 * * *\""
    echo "    prompt: \"Review changes since yesterday, write results to .claude/hooker/cron-results/\""
    exit 1
fi

# Parse schedules from yml (simple parser)
ENTRIES=""
CUR_CRON=""
CUR_PROMPT=""
CUR_NAME=""

flush_entry() {
    [ -z "$CUR_CRON" ] || [ -z "$CUR_PROMPT" ] && return
    ENTRIES="${ENTRIES}${CUR_CRON} cd ${PROJECT_DIR} && claude -p \"${CUR_PROMPT}\" # hooker:${CUR_NAME}
"
}

while IFS= read -r line; do
    case "$line" in
        *"- name:"*)
            flush_entry
            CUR_NAME=$(echo "$line" | sed 's/.*name:[[:space:]]*//' | sed 's/[[:space:]]*$//')
            CUR_CRON="" CUR_PROMPT=""
            ;;
        *"cron:"*)
            CUR_CRON=$(echo "$line" | sed 's/.*cron:[[:space:]]*//' | sed 's/^"//; s/"[[:space:]]*$//')
            ;;
        *"prompt:"*)
            CUR_PROMPT=$(echo "$line" | sed 's/.*prompt:[[:space:]]*//' | sed 's/^"//; s/"[[:space:]]*$//')
            ;;
    esac
done < "$CONFIG"
flush_entry

if [ -z "$ENTRIES" ]; then
    echo "No schedules found in $CONFIG"
    exit 1
fi

# Get current crontab (without our block for this project)
MARKER_START="# @hooker-start ${PROJECT_DIR}"
MARKER_END="# @hooker-end ${PROJECT_DIR}"

CURRENT=$(crontab -l 2>/dev/null || true)

# Remove existing block for this project
CLEANED=$(echo "$CURRENT" | awk -v start="$MARKER_START" -v end="$MARKER_END" '
    $0 == start { skip=1; next }
    $0 == end { skip=0; next }
    !skip { print }
')

# Build new crontab
NEW_CRONTAB="${CLEANED}
${MARKER_START}
${ENTRIES}${MARKER_END}"

# Remove leading/trailing blank lines
NEW_CRONTAB=$(echo "$NEW_CRONTAB" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba;}')

# Install
echo "$NEW_CRONTAB" | crontab -

echo "Crontab updated for ${PROJECT_DIR}:"
echo ""
echo "$ENTRIES"
echo ""
echo "Use 'crontab -l' to verify. Use 'setup-cron.sh' again after editing schedules.yml."

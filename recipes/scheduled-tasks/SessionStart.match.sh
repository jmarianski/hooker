#!/bin/bash
# Scheduled Tasks Manager — auto-install/update crontab from schedules.yml
# SessionStart hook: fires on every session start (recommended async)
# Ensures crontab/schtasks entries match schedules.yml. Idempotent.
source "${HOOKER_HELPERS}"

INPUT=$(cat)

SCHEDULES=".claude/hooker/schedules.yml"
[ -f "$SCHEDULES" ] || exit 1

# Find setup-cron.sh — in plugin or alongside this recipe
RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
SETUP_SCRIPT=""
for candidate in \
    "${CLAUDE_PLUGIN_ROOT:-}/scripts/setup-cron.sh" \
    "${RECIPE_DIR}/setup-cron.sh" \
    ".claude/hooker/setup-cron.sh"; do
    [ -f "$candidate" ] && SETUP_SCRIPT="$candidate" && break
done

[ -z "$SETUP_SCRIPT" ] && exit 1

# Check if crontab is already in sync (skip if markers exist and schedules.yml hasn't changed)
MARKER="# @hooker-start $(pwd)"
if command -v crontab >/dev/null 2>&1; then
    CURRENT=$(crontab -l 2>/dev/null || true)
    if echo "$CURRENT" | grep -q "$MARKER"; then
        # Markers exist — check if schedules.yml is newer than last sync
        SYNC_MARKER=".claude/hooker/.cron-synced"
        if [ -f "$SYNC_MARKER" ] && [ "$SCHEDULES" -ot "$SYNC_MARKER" ]; then
            exit 1  # Already in sync, nothing to do
        fi
    fi
fi

# Run setup-cron.sh silently
bash "$SETUP_SCRIPT" "$SCHEDULES" > /dev/null 2>&1
RESULT=$?

# Mark sync time
touch ".claude/hooker/.cron-synced" 2>/dev/null

if [ "$RESULT" -eq 0 ]; then
    inject "Scheduled tasks synced from schedules.yml to crontab."
fi
exit 0

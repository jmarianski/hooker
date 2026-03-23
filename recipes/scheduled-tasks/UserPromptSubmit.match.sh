#!/bin/bash
# Cron Results Notifier — check for unread results from scheduled sessions
# UserPromptSubmit hook: fires on user messages in interactive sessions
# Only checks once per session (creates .notified marker)
source "${HOOKER_HELPERS}"

INPUT=$(cat)

RESULTS_DIR=".claude/hooker/cron-results"
NOTIFIED_MARKER=".claude/hooker/.cron-notified"

# Skip if no results dir
[ -d "$RESULTS_DIR" ] || exit 1

# Skip if already notified this session
[ -f "$NOTIFIED_MARKER" ] && exit 1

# Count unread results (files not starting with .)
COUNT=$(find "$RESULTS_DIR" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l)
[ "$COUNT" -eq 0 ] && exit 1

# List result files
FILES=$(find "$RESULTS_DIR" -maxdepth 1 -type f ! -name '.*' -printf '%f\n' 2>/dev/null | sort)

# Mark as notified for this session
touch "$NOTIFIED_MARKER"

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
MSG=$(sed -n 's/^unread_results:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG=$(echo "$MSG" | sed "s/{count}/$COUNT/g")

inject "${MSG}
Files:
${FILES}

You can read these files, ask the agent to summarize them, or delete them after review."
exit 0

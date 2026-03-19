#!/bin/bash
# Remind about docs/tests — block stop if last turn had file edits
# Messages are loaded from messages.yml (user-editable)
set -euo pipefail

INPUT=$(cat)

# Prevent infinite loop
echo "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 1

# Check transcript for file modifications in last assistant turn
TRANSCRIPT=$(echo "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 1

# Get last turn: reverse transcript, skip noise, stop at real user prompt
# Real user prompt = has "type":"user" but NOT "tool_result" on same line
LAST_TURN=$(awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}' "$TRANSCRIPT" \
    | grep -v '"type":"progress"' | grep -v '"type":"hook_progress"' \
    | awk '/"type":"user"/ && !/tool_result/{found=1} found{exit} {print}' 2>/dev/null) || true
echo "$LAST_TURN" | grep -q '"name"[[:space:]]*:[[:space:]]*"\(Edit\|Write\|NotebookEdit\)"' || exit 1

# --- Determine what was edited ---
EDITED_FILES=$(echo "$LAST_TURN" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null || true)

HAS_DOCS=false
HAS_TESTS=false
HAS_CODE=false

while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
        *docs/*|*doc/*|*.md|*README*) HAS_DOCS=true ;;
        *__tests__/*|*test*|*spec*) HAS_TESTS=true ;;
        *) HAS_CODE=true ;;
    esac
done <<< "$EDITED_FILES"

# --- Load messages from yml ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Check project override first, then recipe default
MSGS_FILE=".claude/hooker/remind-to-update-docs.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1 || echo "$2"
}

# --- Pick message based on what was edited ---
PARTS=()
if $HAS_CODE && ! $HAS_DOCS && ! $HAS_TESTS; then
    PARTS+=("$(yml_get code_changed 'You edited code — did you update docs and tests?')")
elif $HAS_DOCS && ! $HAS_CODE; then
    PARTS+=("$(yml_get docs_changed 'Are your docs complete and up to date?')")
elif $HAS_TESTS && ! $HAS_CODE; then
    PARTS+=("$(yml_get tests_changed 'Do your tests cover the new cases?')")
else
    PARTS+=("$(yml_get default 'Did you update docs, tests, and clean up TODOs?')")
fi

MSG=$(IFS=' '; echo "${PARTS[*]}")

source "${HOOKER_HELPERS}"
block "Hooker: ${MSG}"
exit 0

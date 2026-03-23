#!/bin/bash
# Directory Cleanup — auto-remove oldest files from bloated directories
# UserPromptSubmit hook: runs periodically on user messages
# DESTRUCTIVE — only acts on rules with action: cleanup in dir-watchdog.yml
source "${HOOKER_HELPERS}"

INPUT=$(cat)

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE=".claude/hooker/dir-watchdog.yml"

# Must have config — never auto-delete without explicit rules
[ -f "$CONFIG_FILE" ] || exit 1

# Frequency control
FREQ=5
F=$(sed -n 's/^check_frequency:[[:space:]]*\([0-9]*\)/\1/p' "$CONFIG_FILE" | head -1)
[ -n "$F" ] && FREQ="$F"
[ "$FREQ" -gt 1 ] 2>/dev/null && [ $((RANDOM % FREQ)) -ne 0 ] && exit 1

THRESHOLD=30
T=$(sed -n 's/^default_threshold:[[:space:]]*\([0-9]*\)/\1/p' "$CONFIG_FILE" | head -1)
[ -n "$T" ] && THRESHOLD="$T"

MSG_CLEANUP=$(sed -n 's/^cleanup_done:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")

RESULT_FILE=$(mktemp 2>/dev/null || echo "/tmp/hooker_dirclean_$$")

# Parse rules — only process action: cleanup
CUR_PATH="" CUR_MAX="$THRESHOLD" CUR_EXT="" CUR_ACTION=""
process_rule() {
    [ -z "$CUR_PATH" ] && return
    [ "$CUR_ACTION" != "cleanup" ] && return
    [ -d "$CUR_PATH" ] || return

    # Count matching files
    local FILES_LIST
    FILES_LIST=$(mktemp 2>/dev/null || echo "/tmp/hooker_flist_$$")

    if [ -n "$CUR_EXT" ]; then
        for ext in $CUR_EXT; do
            find "$CUR_PATH" -maxdepth 1 -name "*.${ext}" -type f -printf '%T@ %p\n' 2>/dev/null >> "$FILES_LIST"
        done
    else
        find "$CUR_PATH" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null > "$FILES_LIST"
    fi

    local COUNT
    COUNT=$(wc -l < "$FILES_LIST")

    if [ "$COUNT" -gt "$CUR_MAX" ]; then
        local EXCESS=$((COUNT - CUR_MAX))
        # Sort by mtime (oldest first), take excess
        local REMOVED=0
        sort -n "$FILES_LIST" | head -"$EXCESS" | while IFS= read -r line; do
            FILE=$(echo "$line" | sed 's/^[^ ]* //')
            rm -f "$FILE" 2>/dev/null && REMOVED=$((REMOVED + 1))
        done
        local KEPT=$((COUNT - EXCESS))
        local MSG=$(echo "$MSG_CLEANUP" | sed "s|{path}|$CUR_PATH|g; s|{removed}|$EXCESS|g; s|{kept}|$KEPT|g; s|{max}|$CUR_MAX|g")
        echo "$MSG" >> "$RESULT_FILE"
    fi

    rm -f "$FILES_LIST" 2>/dev/null
}

while IFS= read -r line; do
    case "$line" in
        *"- path:"*)
            process_rule
            CUR_PATH=$(echo "$line" | sed 's/.*path:[[:space:]]*//' | sed 's/[[:space:]]*$//; s|/$||')
            CUR_MAX="$THRESHOLD" CUR_EXT="" CUR_ACTION=""
            ;;
        *"max_files:"*)
            CUR_MAX=$(echo "$line" | sed 's/.*max_files:[[:space:]]*//' | sed 's/[[:space:]]*$//')
            ;;
        *"extensions:"*)
            CUR_EXT=$(echo "$line" | sed 's/.*\[//; s/\].*//; s/,/ /g; s/[[:space:]]\+/ /g; s/^ //; s/ $//')
            ;;
        *"action:"*)
            CUR_ACTION=$(echo "$line" | sed 's/.*action:[[:space:]]*//' | sed 's/[[:space:]]*$//')
            ;;
    esac
done < "$CONFIG_FILE"
process_rule

RESULTS=$(cat "$RESULT_FILE" 2>/dev/null)
rm -f "$RESULT_FILE" 2>/dev/null

[ -z "$RESULTS" ] && exit 1

inject "$RESULTS"
exit 0

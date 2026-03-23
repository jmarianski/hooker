#!/bin/bash
# Directory Watchdog — warn about directories with too many files
# UserPromptSubmit hook: runs periodically on user messages
# WARN ONLY — never deletes. Use dir-cleanup for auto-removal.
source "${HOOKER_HELPERS}"

INPUT=$(cat)

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE=".claude/hooker/dir-watchdog.yml"

# Frequency control
FREQ=5
if [ -f "$CONFIG_FILE" ]; then
    F=$(sed -n 's/^check_frequency:[[:space:]]*\([0-9]*\)/\1/p' "$CONFIG_FILE" | head -1)
    [ -n "$F" ] && FREQ="$F"
fi
[ "$FREQ" -gt 1 ] 2>/dev/null && [ $((RANDOM % FREQ)) -ne 0 ] && exit 1

# Default threshold
THRESHOLD=30
if [ -f "$CONFIG_FILE" ]; then
    T=$(sed -n 's/^default_threshold:[[:space:]]*\([0-9]*\)/\1/p' "$CONFIG_FILE" | head -1)
    [ -n "$T" ] && THRESHOLD="$T"
fi

# Collect warnings to temp file (avoids subshell variable loss)
WARN_FILE=$(mktemp 2>/dev/null || echo "/tmp/hooker_dirwatch_$$")

# Check a directory, append warning to WARN_FILE
check_dir() {
    local DIR="$1" MAX="$2" EXTS="$3" LABEL="$4"
    [ -d "$DIR" ] || return
    local COUNT=0
    if [ -n "$EXTS" ]; then
        for ext in $EXTS; do
            C=$(find "$DIR" -maxdepth 1 -name "*.${ext}" -type f 2>/dev/null | wc -l)
            COUNT=$((COUNT + C))
        done
    else
        COUNT=$(find "$DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
    fi
    [ "$COUNT" -gt "$MAX" ] && echo "Directory \`${DIR}\` has ${COUNT} ${LABEL:-files} (threshold: ${MAX}).${EXTS:+ Consider adding a cleanup rule.}" >> "$WARN_FILE"
}

# Parse configured rules
CONFIGURED_PATHS=""
if [ -f "$CONFIG_FILE" ]; then
    CUR_PATH="" CUR_MAX="$THRESHOLD" CUR_EXT=""
    while IFS= read -r line; do
        case "$line" in
            *"- path:"*)
                [ -n "$CUR_PATH" ] && check_dir "$CUR_PATH" "$CUR_MAX" "$CUR_EXT" "${CUR_EXT:-files}"
                CUR_PATH=$(echo "$line" | sed 's/.*path:[[:space:]]*//' | sed 's/[[:space:]]*$//; s|/$||')
                CUR_MAX="$THRESHOLD" CUR_EXT=""
                CONFIGURED_PATHS="${CONFIGURED_PATHS}|${CUR_PATH}"
                ;;
            *"max_files:"*)
                CUR_MAX=$(echo "$line" | sed 's/.*max_files:[[:space:]]*//' | sed 's/[[:space:]]*$//')
                ;;
            *"extensions:"*)
                CUR_EXT=$(echo "$line" | sed 's/.*\[//; s/\].*//; s/,/ /g; s/[[:space:]]\+/ /g; s/^ //; s/ $//')
                ;;
        esac
    done < "$CONFIG_FILE"
    [ -n "$CUR_PATH" ] && check_dir "$CUR_PATH" "$CUR_MAX" "$CUR_EXT" "${CUR_EXT:-files}"
fi

# Scan unconfigured directories
if [ "$THRESHOLD" -gt 0 ]; then
    find . -maxdepth 3 -type d \
        ! -path './.git/*' ! -path '*/node_modules/*' ! -path '*/__pycache__/*' \
        ! -path '*/vendor/*' ! -path '*/dist/*' ! -path '*/build/*' \
        ! -path '*/target/*' ! -path '*/.next/*' ! -path '*/.claude/*' \
        ! -name '.*' 2>/dev/null | while IFS= read -r dir; do
        REL=$(echo "$dir" | sed 's|^\./||')
        [ "$REL" = "." ] && continue
        echo "$CONFIGURED_PATHS" | grep -q "|${REL}" && continue
        COUNT=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
        [ "$COUNT" -gt "$THRESHOLD" ] && echo "Directory \`${REL}\` has ${COUNT} files (threshold: ${THRESHOLD}). No rule in dir-watchdog.yml." >> "$WARN_FILE"
    done
fi

WARNINGS=$(cat "$WARN_FILE" 2>/dev/null)
rm -f "$WARN_FILE" 2>/dev/null

[ -z "$WARNINGS" ] && exit 1

inject "$WARNINGS"
exit 0

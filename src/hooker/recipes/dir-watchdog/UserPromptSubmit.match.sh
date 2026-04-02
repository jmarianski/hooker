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

# Parse global ignore patterns
GLOBAL_IGNORE=""
if [ -f "$CONFIG_FILE" ]; then
    GLOBAL_IGNORE=$(sed -n 's/^ignore:[[:space:]]*\[//p' "$CONFIG_FILE" | sed 's/\].*//; s/,/ /g; s/[[:space:]]\+/ /g; s/^ //; s/ $//' | head -1)
fi

# Collect warnings to temp file (avoids subshell variable loss)
WARN_FILE=$(mktemp 2>/dev/null || echo "/tmp/hooker_dirwatch_$$")

# Check if filename matches any ignore pattern (supports * glob)
is_ignored() {
    local FNAME="$1" PATTERNS="$2"
    [ -z "$PATTERNS" ] && return 1
    for pat in $PATTERNS; do
        case "$FNAME" in
            $pat) return 0 ;;
        esac
    done
    return 1
}

# Count files in directory, excluding ignored
count_files() {
    local DIR="$1" EXTS="$2" IGNORE="$3"
    local COUNT=0
    local ALL_IGNORE="${GLOBAL_IGNORE} ${IGNORE}"

    find "$DIR" -maxdepth 1 -type f 2>/dev/null | while IFS= read -r fpath; do
        FNAME=$(basename "$fpath")
        is_ignored "$FNAME" "$ALL_IGNORE" && continue
        if [ -n "$EXTS" ]; then
            EXT=$(echo "$FNAME" | sed 's/.*\.//' | tr '[:upper:]' '[:lower:]')
            echo "$EXTS" | grep -qw "$EXT" || continue
        fi
        echo "$fpath"
    done | wc -l
}

# Check a directory, append warning to WARN_FILE
check_dir() {
    local DIR="$1" MAX="$2" EXTS="$3" IGNORE="$4"
    [ -d "$DIR" ] || return
    local COUNT
    COUNT=$(count_files "$DIR" "$EXTS" "$IGNORE")
    [ "$COUNT" -gt "$MAX" ] && echo "Directory \`${DIR}\` has ${COUNT} files (threshold: ${MAX})." >> "$WARN_FILE"
}

# Parse configured rules
CONFIGURED_PATHS=""
if [ -f "$CONFIG_FILE" ]; then
    CUR_PATH="" CUR_MAX="$THRESHOLD" CUR_EXT="" CUR_IGNORE=""
    while IFS= read -r line; do
        case "$line" in
            *"- path:"*)
                [ -n "$CUR_PATH" ] && check_dir "$CUR_PATH" "$CUR_MAX" "$CUR_EXT" "$CUR_IGNORE"
                CUR_PATH=$(echo "$line" | sed 's/.*path:[[:space:]]*//' | sed 's/[[:space:]]*$//; s|/$||')
                CUR_MAX="$THRESHOLD" CUR_EXT="" CUR_IGNORE=""
                CONFIGURED_PATHS="${CONFIGURED_PATHS}|${CUR_PATH}"
                ;;
            *"max_files:"*)
                CUR_MAX=$(echo "$line" | sed 's/.*max_files:[[:space:]]*//' | sed 's/[[:space:]]*$//')
                ;;
            *"extensions:"*)
                CUR_EXT=$(echo "$line" | sed 's/.*\[//; s/\].*//; s/,/ /g; s/[[:space:]]\+/ /g; s/^ //; s/ $//')
                ;;
            *"ignore:"*)
                CUR_IGNORE=$(echo "$line" | sed 's/.*\[//; s/\].*//; s/,/ /g; s/[[:space:]]\+/ /g; s/^ //; s/ $//')
                ;;
        esac
    done < "$CONFIG_FILE"
    [ -n "$CUR_PATH" ] && check_dir "$CUR_PATH" "$CUR_MAX" "$CUR_EXT" "$CUR_IGNORE"
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
        COUNT=$(count_files "$dir" "" "")
        [ "$COUNT" -gt "$THRESHOLD" ] && echo "Directory \`${REL}\` has ${COUNT} files (threshold: ${THRESHOLD}). No rule in dir-watchdog.yml." >> "$WARN_FILE"
    done
fi

WARNINGS=$(cat "$WARN_FILE" 2>/dev/null)
rm -f "$WARN_FILE" 2>/dev/null

[ -z "$WARNINGS" ] && exit 1

# Add config hint if no config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    MSG_HINT=$(sed -n 's/^no_config_hint:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
    WARNINGS="${WARNINGS}
${MSG_HINT}"
fi

inject "$WARNINGS"
exit 0

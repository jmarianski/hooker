#!/bin/bash
# Refactor Move Universal — update path references in any text file after mv
# Catches config files, YAML, Dockerfiles, scripts, etc.
# Skips binary files and common generated directories.
source "${HOOKER_HELPERS}"

INPUT=$(cat)

TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" = "Bash" ] || exit 1

CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Strip cd chains, env vars, flags, handle git mv
MV_CMD=$(echo "$CMD" | sed 's/^[^;|&]*&&[[:space:]]*//' | sed 's/^[A-Z_]*=[^[:space:]]*[[:space:]]*//')
MV_CMD=$(echo "$MV_CMD" | sed 's/^[A-Z_]*=[^[:space:]]*[[:space:]]*//')
MV_CMD=$(echo "$MV_CMD" | sed 's/^git[[:space:]]\+mv/mv/')
echo "$CMD" | grep -q 'HOOKER_NO_REFACTOR=1' && exit 1
MV_ARGS=$(echo "$MV_CMD" | sed 's/^mv[[:space:]]\+//; s/^-[a-zA-Z]\+[[:space:]]*//g; s/^--[a-zA-Z-]\+[[:space:]]*//g')

# Detect: mv old_path new_path
OLD_PATH=$(echo "$MV_ARGS" | sed -n 's/^\([^[:space:]]\+\)[[:space:]]\+.*/\1/p')
NEW_PATH=$(echo "$MV_ARGS" | sed -n 's/^[^[:space:]]\+[[:space:]]\+\([^[:space:]]\+\)/\1/p')
[ -z "$OLD_PATH" ] || [ -z "$NEW_PATH" ] && exit 1

if [ -d "$NEW_PATH" ]; then
    NEW_PATH="${NEW_PATH%/}/$(basename "$OLD_PATH")"
fi

# Normalize paths
OLD_CLEAN=$(echo "$OLD_PATH" | sed 's|^\./||')
NEW_CLEAN=$(echo "$NEW_PATH" | sed 's|^\./||')
[ "$OLD_CLEAN" = "$NEW_CLEAN" ] && exit 1

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
MSG_UPDATED=$(sed -n 's/^updated:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_REFS=$(sed -n 's/^no_refs:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")

# Escape dots for grep/sed regex
OLD_ESC=$(echo "$OLD_CLEAN" | sed 's/\./\\./g')

# Search in text files only, skip common generated/binary directories
AFFECTED_FILES=$(grep -rl "${OLD_CLEAN}" . 2>/dev/null \
    | grep -v '\.git/' \
    | grep -v 'node_modules/' \
    | grep -v '__pycache__/' \
    | grep -v '/vendor/' \
    | grep -v '/dist/' \
    | grep -v '/build/' \
    | grep -v '/target/' \
    | grep -v '/bin/' \
    | grep -v '/obj/' \
    | grep -v '\.next/' \
    | grep -v '\.lock$' \
    | grep -v '\.min\.' \
    || true)

# Filter to text files only (skip binaries)
TEXT_FILES=""
while IFS= read -r file; do
    [ -z "$file" ] && continue
    # Skip the moved file itself
    [ "$file" = "./$NEW_CLEAN" ] || [ "$file" = "$NEW_CLEAN" ] && continue
    # Quick binary check: skip files with null bytes in first 512 bytes
    head -c 512 "$file" 2>/dev/null | grep -q "$(printf '\0')" && continue
    TEXT_FILES="${TEXT_FILES}${file}
"
done <<< "$AFFECTED_FILES"

[ -z "$TEXT_FILES" ] && {
    inject "$MSG_NO_REFS"
    exit 0
}

COUNT=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    if grep -q "${OLD_ESC}" "$file" 2>/dev/null; then
        _hooker_sed_i "s|${OLD_CLEAN}|${NEW_CLEAN}|g" "$file" 2>/dev/null
        COUNT=$((COUNT + 1))
    fi
done <<< "$TEXT_FILES"

if [ "$COUNT" -gt 0 ]; then
    MSG=$(echo "$MSG_UPDATED" | sed "s/{count}/$COUNT/g")
    inject "Refactor Move (universal): ${MSG}"
else
    inject "$MSG_NO_REFS"
fi
exit 0

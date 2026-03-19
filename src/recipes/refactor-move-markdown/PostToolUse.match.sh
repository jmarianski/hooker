#!/bin/bash
# Refactor Move Markdown Links — update [text](path) refs after mv
# PostToolUse hook: fires after Bash tool completes
# Pure bash/sed — no external dependencies.
source "${HOOKER_HELPERS}"

INPUT=$(cat)

# Only act on Bash tool
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" = "Bash" ] || exit 1

# Extract command
CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Strip leading env vars (VAR=val), cd chains (cd dir &&), and mv flags
MV_CMD=$(echo "$CMD" | sed 's/^[^;|&]*&&[[:space:]]*//' | sed 's/^[A-Z_]*=[^[:space:]]*[[:space:]]*//')
MV_CMD=$(echo "$MV_CMD" | sed 's/^[A-Z_]*=[^[:space:]]*[[:space:]]*//')
MV_CMD=$(echo "$MV_CMD" | sed 's/^git[[:space:]]\+mv/mv/')
echo "$CMD" | grep -q 'HOOKER_NO_REFACTOR=1' && exit 1
MV_ARGS=$(echo "$MV_CMD" | sed 's/^mv[[:space:]]\+//; s/^-[a-zA-Z]\+[[:space:]]*//g; s/^--[a-zA-Z-]\+[[:space:]]*//g')

# Detect: mv old_path new_path
OLD_PATH=$(echo "$MV_ARGS" | sed -n 's/^\([^[:space:]]\+\)[[:space:]]\+.*/\1/p')
NEW_PATH=$(echo "$MV_ARGS" | sed -n 's/^[^[:space:]]\+[[:space:]]\+\([^[:space:]]\+\)/\1/p')
[ -z "$OLD_PATH" ] || [ -z "$NEW_PATH" ] && exit 1

# If new path is a directory, append the filename
if [ -d "$NEW_PATH" ]; then
    NEW_PATH="${NEW_PATH%/}/$(basename "$OLD_PATH")"
fi

# Strip leading ./ for consistency
OLD_CLEAN=$(echo "$OLD_PATH" | sed 's|^\./||')
NEW_CLEAN=$(echo "$NEW_PATH" | sed 's|^\./||')
[ "$OLD_CLEAN" = "$NEW_CLEAN" ] && exit 1

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
MSG_UPDATED=$(sed -n 's/^updated:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_REFS=$(sed -n 's/^no_refs:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")

# Get basename for initial grep filter (fast pre-filter)
OLD_BASENAME=$(basename "$OLD_CLEAN")

# Find markdown files containing references to the old path
AFFECTED_FILES=$(grep -rl "${OLD_BASENAME}" --include='*.md' . 2>/dev/null \
    | grep -v node_modules | grep -v '.git/' | grep -v vendor || true)

[ -z "$AFFECTED_FILES" ] && {
    inject "$MSG_NO_REFS"
    exit 0
}

COUNT=0
while IFS= read -r mdfile; do
    [ -z "$mdfile" ] && continue

    MD_DIR=$(dirname "$mdfile" | sed 's|^\./||')

    # Compute relative paths from this markdown file's directory
    # Old relative path (what the link currently says)
    # New relative path (what it should say)
    if command -v python3 >/dev/null 2>&1; then
        OLD_REL=$(python3 -c "import sys,os.path; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$OLD_CLEAN" "$MD_DIR" 2>/dev/null)
        NEW_REL=$(python3 -c "import sys,os.path; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$NEW_CLEAN" "$MD_DIR" 2>/dev/null)
    else
        # Without python3, try direct path if in same/child directory
        OLD_REL="$OLD_CLEAN"
        NEW_REL="$NEW_CLEAN"
    fi

    [ -z "$OLD_REL" ] || [ -z "$NEW_REL" ] && continue
    [ "$OLD_REL" = "$NEW_REL" ] && continue

    # Escape dots in paths for sed regex
    OLD_REL_ESC=$(echo "$OLD_REL" | sed 's/\./\\./g')

    # Match markdown link patterns: [text](path) and ![alt](path)
    # Also handle paths with anchors: [text](path#section)
    if grep -q "\](\(\.*/\)*${OLD_BASENAME}" "$mdfile" 2>/dev/null; then
        # Replace exact relative path in markdown links (preserve anchors/query strings)
        _hooker_sed_i "s|\](${OLD_REL_ESC})|](${NEW_REL})|g; s|\](${OLD_REL_ESC}#|\](${NEW_REL}#|g; s|\](${OLD_REL_ESC}?|\](${NEW_REL}?|g" "$mdfile" 2>/dev/null

        # Also try with ./ prefix
        OLD_REL_ESC_DOT=$(echo "./${OLD_REL}" | sed 's/\./\\./g')
        _hooker_sed_i "s|\](${OLD_REL_ESC_DOT})|](./${NEW_REL})|g" "$mdfile" 2>/dev/null

        COUNT=$((COUNT + 1))
    fi
done <<< "$AFFECTED_FILES"

if [ "$COUNT" -gt 0 ]; then
    MSG=$(echo "$MSG_UPDATED" | sed "s/{count}/$COUNT/g")
    inject "Refactor Move (markdown): ${MSG}"
else
    inject "$MSG_NO_REFS"
fi
exit 0

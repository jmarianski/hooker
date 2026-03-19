#!/bin/bash
# Refactor Move JS/TS (smart) — AST-aware import rewriting via ts-morph
# PostToolUse hook: fires after Bash tool completes
# Falls back to simple sed if ts-morph is not installed.
source "${HOOKER_HELPERS}"

INPUT=$(cat)

# Only act on Bash tool
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" = "Bash" ] || exit 1

# Extract command
CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Detect: mv old_path new_path (simple two-arg mv on JS/TS files)
OLD_PATH=$(echo "$CMD" | sed -n 's/^mv[[:space:]]\+\([^[:space:]]\+\.[jt]sx\{0,1\}\)[[:space:]]\+.*/\1/p')
NEW_PATH=$(echo "$CMD" | sed -n 's/^mv[[:space:]]\+[^[:space:]]\+[[:space:]]\+\([^[:space:]]\+\)/\1/p')
[ -z "$OLD_PATH" ] || [ -z "$NEW_PATH" ] && exit 1

# If new path is a directory, append the filename
if [ -d "$NEW_PATH" ]; then
    NEW_PATH="${NEW_PATH%/}/$(basename "$OLD_PATH")"
fi

# Strip extensions for comparison
strip_ext() {
    echo "$1" | sed 's/\.\(ts\|tsx\|js\|jsx\)$//'
}

OLD_IMPORT=$(strip_ext "$OLD_PATH")
NEW_IMPORT=$(strip_ext "$NEW_PATH")
[ "$OLD_IMPORT" = "$NEW_IMPORT" ] && exit 1

# Load messages
RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
MSG_UPDATED=$(sed -n 's/^updated:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_REFS=$(sed -n 's/^no_refs:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_TSMORPH=$(sed -n 's/^no_tsmorph:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")

# --- Try ts-morph first ---
SCRIPT_PATH="${RECIPE_DIR}/update-imports.mjs"

if [ -f "$SCRIPT_PATH" ] && command -v node >/dev/null 2>&1; then
    # Check if ts-morph is available
    if node -e "require('ts-morph')" 2>/dev/null; then
        RESULT=$(node "$SCRIPT_PATH" "$OLD_PATH" "$NEW_PATH" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$RESULT" ]; then
            COUNT=$(echo "$RESULT" | sed -n 's/.*"count"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
            if [ "$COUNT" -gt 0 ] 2>/dev/null; then
                MSG=$(echo "$MSG_UPDATED" | sed "s/{count}/$COUNT/g")
                inject "Refactor Move (ts-morph): ${MSG} Files: $(echo "$RESULT" | sed -n 's/.*"files"[[:space:]]*:[[:space:]]*\[\(.*\)\].*/\1/p')"
                exit 0
            else
                inject "$MSG_NO_REFS"
                exit 0
            fi
        fi
    else
        # ts-morph not installed — warn and fall through to sed
        inject "$MSG_NO_TSMORPH"
    fi
fi

# --- Fallback: simple sed-based approach ---
OLD_IMPORT_CLEAN=$(echo "$OLD_IMPORT" | sed 's|^\./||')
NEW_IMPORT_CLEAN=$(echo "$NEW_IMPORT" | sed 's|^\./||')

OLD_BASENAME=$(basename "$OLD_IMPORT_CLEAN")

# Find files referencing old import path
AFFECTED_FILES=$(grep -rl "['\"]\.\{0,2\}/.*${OLD_BASENAME}['\"]" \
    --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
    . 2>/dev/null | grep -v node_modules | grep -v '.git/' || true)

[ -z "$AFFECTED_FILES" ] && {
    inject "$MSG_NO_REFS"
    exit 0
}

COUNT=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    FILE_DIR=$(dirname "$file")

    # Compute relative paths (try python3, fall back to basename-based)
    OLD_REL=$(python3 -c "import os.path; print(os.path.relpath('$OLD_IMPORT_CLEAN', '$FILE_DIR'))" 2>/dev/null) || OLD_REL="$OLD_IMPORT_CLEAN"
    NEW_REL=$(python3 -c "import os.path; print(os.path.relpath('$NEW_IMPORT_CLEAN', '$FILE_DIR'))" 2>/dev/null) || NEW_REL="$NEW_IMPORT_CLEAN"

    case "$OLD_REL" in ./*|../*) ;; *) OLD_REL="./${OLD_REL}" ;; esac
    case "$NEW_REL" in ./*|../*) ;; *) NEW_REL="./${NEW_REL}" ;; esac

    if grep -q "['\"]\(${OLD_REL}\)['\"]" "$file" 2>/dev/null; then
        sed -i "s|'${OLD_REL}'|'${NEW_REL}'|g; s|\"${OLD_REL}\"|\"${NEW_REL}\"|g" "$file" 2>/dev/null
        COUNT=$((COUNT + 1))
    fi
done <<< "$AFFECTED_FILES"

if [ "$COUNT" -gt 0 ]; then
    MSG=$(echo "$MSG_UPDATED" | sed "s/{count}/$COUNT/g")
    inject "Refactor Move (sed fallback): ${MSG}"
else
    inject "$MSG_NO_REFS"
fi
exit 0

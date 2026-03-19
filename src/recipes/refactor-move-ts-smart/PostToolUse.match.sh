#!/bin/bash
# Refactor Move JS/TS (smart) — TypeScript Language Service API
# PostToolUse hook: fires after Bash tool completes
# Uses getEditsForFileRename() — same mechanism as VS Code
# Handles single files and directory moves.
# Falls back to simple sed if typescript is not available.
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

# Detect: mv old_path new_path (two-arg mv)
OLD_PATH=$(echo "$MV_ARGS" | sed -n 's/^\([^[:space:]]\+\)[[:space:]]\+.*/\1/p')
NEW_PATH=$(echo "$MV_ARGS" | sed -n 's/^[^[:space:]]\+[[:space:]]\+\([^[:space:]]\+\)/\1/p')
[ -z "$OLD_PATH" ] || [ -z "$NEW_PATH" ] && exit 1

# Must be a JS/TS file OR a directory containing JS/TS files
is_ts_file() { echo "$1" | grep -q '\.[jt]sx\{0,1\}$'; }
has_ts_files() { [ -d "$1" ] && find "$1" -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' 2>/dev/null | head -1 | grep -q .; }

if is_ts_file "$OLD_PATH"; then
    # Single file move — if new path is a directory, append filename
    if [ -d "$NEW_PATH" ]; then
        NEW_PATH="${NEW_PATH%/}/$(basename "$OLD_PATH")"
    fi
elif [ -d "$NEW_PATH" ] && ! [ -d "$OLD_PATH" ]; then
    # OLD was a directory (now at NEW) — check if it has TS files
    has_ts_files "$NEW_PATH" || exit 1
else
    exit 1
fi

# For single files: strip extensions for comparison
strip_ext() { echo "$1" | sed 's/\.\(ts\|tsx\|js\|jsx\)$//'; }

if is_ts_file "$OLD_PATH"; then
    OLD_IMPORT=$(strip_ext "$OLD_PATH")
    NEW_IMPORT=$(strip_ext "$NEW_PATH")
    [ "$OLD_IMPORT" = "$NEW_IMPORT" ] && exit 1
fi

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load messages
MSG_UPDATED=$(sed -n 's/^updated:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_REFS=$(sed -n 's/^no_refs:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_TS=$(sed -n 's/^no_typescript:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")

# --- Try TypeScript Language Service (getEditsForFileRename) ---
if command -v node >/dev/null 2>&1 && node -e "require('typescript')" 2>/dev/null; then
    RESULT=$(node "${RECIPE_DIR}/update-imports.cjs" "$OLD_PATH" "$NEW_PATH" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$RESULT" ]; then
        COUNT=$(echo "$RESULT" | sed -n 's/.*"count"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
        if [ "$COUNT" -gt 0 ] 2>/dev/null; then
            FILES=$(echo "$RESULT" | sed -n 's/.*"files"[[:space:]]*:[[:space:]]*\[\(.*\)\].*/\1/p')
            inject "Refactor Move (TS Language Service): Updated imports in ${COUNT} files. Files: ${FILES}"
            exit 0
        else
            inject "$MSG_NO_REFS"
            exit 0
        fi
    fi
fi

# --- Fallback: simple sed (single file only, not directories) ---
if ! is_ts_file "$OLD_PATH"; then
    inject "typescript not available and directory moves cannot use sed fallback. Install typescript: npm i -g typescript"
    exit 0
fi

OLD_IMPORT_CLEAN=$(echo "$OLD_IMPORT" | sed 's|^\./||')
NEW_IMPORT_CLEAN=$(echo "$NEW_IMPORT" | sed 's|^\./||')
OLD_BASENAME=$(basename "$OLD_IMPORT_CLEAN")

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
    OLD_REL=$(python3 -c "import sys,os.path; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$OLD_IMPORT_CLEAN" "$FILE_DIR" 2>/dev/null) || OLD_REL="$OLD_IMPORT_CLEAN"
    NEW_REL=$(python3 -c "import sys,os.path; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$NEW_IMPORT_CLEAN" "$FILE_DIR" 2>/dev/null) || NEW_REL="$NEW_IMPORT_CLEAN"
    case "$OLD_REL" in ./*|../*) ;; *) OLD_REL="./${OLD_REL}" ;; esac
    case "$NEW_REL" in ./*|../*) ;; *) NEW_REL="./${NEW_REL}" ;; esac
    if grep -q "['\"]\(${OLD_REL}\)['\"]" "$file" 2>/dev/null; then
        _hooker_sed_i "s|'${OLD_REL}'|'${NEW_REL}'|g; s|\"${OLD_REL}\"|\"${NEW_REL}\"|g" "$file" 2>/dev/null
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

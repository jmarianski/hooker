#!/bin/bash
# Refactor Move (JS/TS) — update imports after mv
# PostToolUse hook: fires after Bash tool completes
# NOTE: Uses python3 for reliable relative path computation.
# Falls back to simpler sed-based approach if python3 unavailable.
source "${HOOKER_HELPERS}"

INPUT=$(cat)

# Only act on Bash tool
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" = "Bash" ] || exit 1

# Skip refactoring if explicitly disabled
[ "${HOOKER_NO_REFACTOR:-}" = "1" ] && exit 1

# Extract command
CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Detect: mv old_path new_path (simple two-arg mv on JS/TS files)
OLD_PATH=$(echo "$CMD" | sed -n 's/^mv[[:space:]]\+\([^[:space:]]\+\.[jt]sx\{0,1\}\)[[:space:]]\+.*/\1/p')
NEW_PATH=$(echo "$CMD" | sed -n 's/^mv[[:space:]]\+[^[:space:]]\+[[:space:]]\+\([^[:space:]]\+\)/\1/p')
[ -z "$OLD_PATH" ] || [ -z "$NEW_PATH" ] && exit 1

# If new path is a directory, append the filename
if [ -d "$NEW_PATH" ]; then
    NEW_PATH="${NEW_PATH}/$(basename "$OLD_PATH")"
fi

# Strip extensions for import paths
strip_ext() {
    echo "$1" | sed 's/\.\(ts\|tsx\|js\|jsx\)$//'
}

OLD_IMPORT=$(strip_ext "$OLD_PATH")
NEW_IMPORT=$(strip_ext "$NEW_PATH")
[ "$OLD_IMPORT" = "$NEW_IMPORT" ] && exit 1

# Strip leading ./ for consistency
OLD_IMPORT=$(echo "$OLD_IMPORT" | sed 's|^\./||')
NEW_IMPORT=$(echo "$NEW_IMPORT" | sed 's|^\./||')

# --- Try to read tsconfig path aliases ---
# Looks for baseUrl and paths in tsconfig.json for non-relative imports
TSCONFIG=""
for f in tsconfig.json tsconfig.app.json tsconfig.base.json; do
    [ -f "$f" ] && TSCONFIG="$f" && break
done

BASE_URL=""
if [ -n "$TSCONFIG" ]; then
    BASE_URL=$(sed -n 's/.*"baseUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TSCONFIG" | head -1)
fi

# --- Build search pattern ---
OLD_BASENAME=$(basename "$OLD_IMPORT")

# Find files referencing old import path
AFFECTED_FILES=$(grep -rl "['\"]\.\{0,2\}/.*${OLD_BASENAME}['\"]" \
    --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
    . 2>/dev/null | grep -v node_modules | grep -v '.git/' || true)

# Also search for tsconfig alias-style imports (non-relative)
if [ -n "$BASE_URL" ]; then
    ALIAS_FILES=$(grep -rl "['\"]\(${OLD_IMPORT}\|@.*/.*${OLD_BASENAME}\)['\"]" \
        --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
        . 2>/dev/null | grep -v node_modules | grep -v '.git/' || true)
    AFFECTED_FILES=$(printf '%s\n%s' "$AFFECTED_FILES" "$ALIAS_FILES" | sort -u)
fi

[ -z "$AFFECTED_FILES" ] && {
    inject "File moved from ${OLD_PATH} to ${NEW_PATH}. No import references found to update."
    exit 0
}

# --- Update imports ---
COUNT=0
while IFS= read -r file; do
    [ -z "$file" ] && continue

    FILE_DIR=$(dirname "$file")

    # Compute relative paths using python3 (reliable) or fallback
    OLD_REL=$(python3 -c "import os.path; print(os.path.relpath('$OLD_IMPORT', '$FILE_DIR'))" 2>/dev/null) || OLD_REL="$OLD_IMPORT"
    NEW_REL=$(python3 -c "import os.path; print(os.path.relpath('$NEW_IMPORT', '$FILE_DIR'))" 2>/dev/null) || NEW_REL="$NEW_IMPORT"

    # Ensure relative paths start with ./
    case "$OLD_REL" in ./*|../*) ;; *) OLD_REL="./${OLD_REL}" ;; esac
    case "$NEW_REL" in ./*|../*) ;; *) NEW_REL="./${NEW_REL}" ;; esac

    # Replace in file (both quote styles)
    if grep -q "['\"]\(${OLD_REL}\)['\"]" "$file" 2>/dev/null; then
        sed -i "s|'${OLD_REL}'|'${NEW_REL}'|g; s|\"${OLD_REL}\"|\"${NEW_REL}\"|g" "$file" 2>/dev/null
        COUNT=$((COUNT + 1))
    fi
done <<< "$AFFECTED_FILES"

if [ "$COUNT" -gt 0 ]; then
    inject "Refactor Move: updated imports in ${COUNT} files after moving ${OLD_PATH} → ${NEW_PATH}."
else
    inject "File moved from ${OLD_PATH} to ${NEW_PATH}. Found references but could not auto-update — check imports manually."
fi
exit 0

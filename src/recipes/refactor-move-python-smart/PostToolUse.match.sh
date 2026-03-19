#!/bin/bash
# Refactor Move Python (smart) — AST-aware import rewriting via rope
# PostToolUse hook: fires after Bash tool completes
# Falls back to simple sed if rope is not available.
source "${HOOKER_HELPERS}"

INPUT=$(cat)

# Only act on Bash tool
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" = "Bash" ] || exit 1

# Skip refactoring if explicitly disabled
[ "${HOOKER_NO_REFACTOR:-}" = "1" ] && exit 1

# Extract command
CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Detect: mv old.py new.py
OLD_PATH=$(echo "$CMD" | sed -n 's/^mv[[:space:]]\+\([^[:space:]]\+\.py\)[[:space:]]\+.*/\1/p')
NEW_PATH=$(echo "$CMD" | sed -n 's/^mv[[:space:]]\+[^[:space:]]\+[[:space:]]\+\([^[:space:]]\+\)/\1/p')
[ -z "$OLD_PATH" ] || [ -z "$NEW_PATH" ] && exit 1

if [ -d "$NEW_PATH" ]; then
    NEW_PATH="${NEW_PATH%/}/$(basename "$OLD_PATH")"
fi

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load messages
MSG_UPDATED=$(sed -n 's/^updated:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_REFS=$(sed -n 's/^no_refs:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_ROPE=$(sed -n 's/^no_rope:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")

# --- Try rope first ---
if command -v python3 >/dev/null 2>&1 && python3 -c "import rope" 2>/dev/null; then
    RESULT=$(python3 "${RECIPE_DIR}/rope-move.py" "$(pwd)" "$OLD_PATH" "$NEW_PATH" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$RESULT" ]; then
        COUNT=$(echo "$RESULT" | sed -n 's/.*"count"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
        if [ "$COUNT" -gt 0 ] 2>/dev/null; then
            FILES=$(echo "$RESULT" | sed -n 's/.*"files"[[:space:]]*:[[:space:]]*\[\(.*\)\].*/\1/p')
            inject "Refactor Move (rope): Updated imports in ${COUNT} files. Files: ${FILES}"
            exit 0
        else
            inject "$MSG_NO_REFS"
            exit 0
        fi
    fi
    # rope failed — fall through to sed
fi

# Warn if rope not available
if ! python3 -c "import rope" 2>/dev/null; then
    inject "$MSG_NO_ROPE"
fi

# --- Fallback: simple sed ---
to_module() {
    echo "$1" | sed 's|/|.|g; s|\.py$||; s|^\.\.*||; s|^\.||'
}

OLD_MOD=$(to_module "$OLD_PATH")
NEW_MOD=$(to_module "$NEW_PATH")
[ "$OLD_MOD" = "$NEW_MOD" ] && exit 1

OLD_NAME=$(basename "$OLD_PATH" .py)
NEW_NAME=$(basename "$NEW_PATH" .py)

AFFECTED_FILES=$(grep -rl "\(import\|from\).*${OLD_NAME}" \
    --include='*.py' . 2>/dev/null | grep -v __pycache__ | grep -v '.git/' || true)

[ -z "$AFFECTED_FILES" ] && {
    inject "$MSG_NO_REFS"
    exit 0
}

COUNT=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    CHANGED=false

    if grep -q "from[[:space:]]\+${OLD_MOD}[[:space:]]\+import" "$file" 2>/dev/null; then
        sed -i "s|from ${OLD_MOD} import|from ${NEW_MOD} import|g" "$file" 2>/dev/null
        CHANGED=true
    fi

    if grep -q "import[[:space:]]\+${OLD_MOD}" "$file" 2>/dev/null; then
        sed -i "s|import ${OLD_MOD}|import ${NEW_MOD}|g" "$file" 2>/dev/null
        CHANGED=true
    fi

    OLD_PARENT=$(echo "$OLD_MOD" | sed 's|\.[^.]*$||')
    NEW_PARENT=$(echo "$NEW_MOD" | sed 's|\.[^.]*$||')
    if [ "$OLD_PARENT" != "$OLD_MOD" ] && grep -q "from[[:space:]]\+${OLD_PARENT}[[:space:]]\+import.*${OLD_NAME}" "$file" 2>/dev/null; then
        sed -i "s|from ${OLD_PARENT} import \(.*\)${OLD_NAME}|from ${NEW_PARENT} import \1${NEW_NAME}|g" "$file" 2>/dev/null
        CHANGED=true
    fi

    $CHANGED && COUNT=$((COUNT + 1))
done <<< "$AFFECTED_FILES"

if [ "$COUNT" -gt 0 ]; then
    MSG=$(echo "$MSG_UPDATED" | sed "s/{count}/$COUNT/g")
    inject "Refactor Move (sed fallback): ${MSG}"
else
    inject "$MSG_NO_REFS"
fi
exit 0

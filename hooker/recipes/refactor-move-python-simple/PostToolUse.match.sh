#!/bin/bash
# Refactor Move (Python) — update imports after mv
source "${HOOKER_HELPERS}"

INPUT=$(cat)

TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" = "Bash" ] || exit 1

CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Strip leading env vars (VAR=val), cd chains (cd dir &&), and mv flags
MV_CMD=$(echo "$CMD" | sed 's/^[^;|&]*&&[[:space:]]*//' | sed 's/^[A-Z_]*=[^[:space:]]*[[:space:]]*//')
MV_CMD=$(echo "$MV_CMD" | sed 's/^[A-Z_]*=[^[:space:]]*[[:space:]]*//')
MV_CMD=$(echo "$MV_CMD" | sed 's/^git[[:space:]]\+mv/mv/')
echo "$CMD" | grep -q 'HOOKER_NO_REFACTOR=1' && exit 1
MV_ARGS=$(echo "$MV_CMD" | sed 's/^mv[[:space:]]\+//; s/^-[a-zA-Z]\+[[:space:]]*//g; s/^--[a-zA-Z-]\+[[:space:]]*//g')

# Detect: mv old.py new.py
OLD_PATH=$(echo "$MV_ARGS" | sed -n 's/^\([^[:space:]]\+\.py\)[[:space:]]\+.*/\1/p')
NEW_PATH=$(echo "$MV_ARGS" | sed -n 's/^[^[:space:]]\+[[:space:]]\+\([^[:space:]]\+\)/\1/p')
[ -z "$OLD_PATH" ] || [ -z "$NEW_PATH" ] && exit 1

if [ -d "$NEW_PATH" ]; then
    NEW_PATH="${NEW_PATH}/$(basename "$OLD_PATH")"
fi

# Convert file paths to Python module paths (src/utils/helper.py → src.utils.helper)
to_module() {
    echo "$1" | sed 's|/|.|g; s|\.py$||; s|^\.\.*||; s|^\.||'
}

OLD_MOD=$(to_module "$OLD_PATH")
NEW_MOD=$(to_module "$NEW_PATH")
[ "$OLD_MOD" = "$NEW_MOD" ] && exit 1

# Also get the last component (for "from X import Y" patterns)
OLD_NAME=$(basename "$OLD_PATH" .py)
NEW_NAME=$(basename "$NEW_PATH" .py)

# Find Python files referencing old module
AFFECTED_FILES=$(grep -rl "\(import\|from\).*${OLD_NAME}" \
    --include='*.py' . 2>/dev/null | grep -v __pycache__ | grep -v '.git/' || true)

[ -z "$AFFECTED_FILES" ] && {
    inject "File moved from ${OLD_PATH} to ${NEW_PATH}. No Python import references found."
    exit 0
}

COUNT=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    CHANGED=false

    # Replace "from old.module import X" → "from new.module import X"
    if grep -q "from[[:space:]]\+${OLD_MOD}[[:space:]]\+import" "$file" 2>/dev/null; then
        _hooker_sed_i "s|from ${OLD_MOD} import|from ${NEW_MOD} import|g" "$file" 2>/dev/null
        CHANGED=true
    fi

    # Replace "import old.module" → "import new.module"
    if grep -q "import[[:space:]]\+${OLD_MOD}" "$file" 2>/dev/null; then
        _hooker_sed_i "s|import ${OLD_MOD}|import ${NEW_MOD}|g" "$file" 2>/dev/null
        CHANGED=true
    fi

    # Replace "from old.parent import old_name" → "from new.parent import new_name"
    OLD_PARENT=$(echo "$OLD_MOD" | sed 's|\.[^.]*$||')
    NEW_PARENT=$(echo "$NEW_MOD" | sed 's|\.[^.]*$||')
    if [ "$OLD_PARENT" != "$OLD_MOD" ] && grep -q "from[[:space:]]\+${OLD_PARENT}[[:space:]]\+import.*${OLD_NAME}" "$file" 2>/dev/null; then
        _hooker_sed_i "s|from ${OLD_PARENT} import \(.*\)${OLD_NAME}|from ${NEW_PARENT} import \1${NEW_NAME}|g" "$file" 2>/dev/null
        CHANGED=true
    fi

    $CHANGED && COUNT=$((COUNT + 1))
done <<< "$AFFECTED_FILES"

if [ "$COUNT" -gt 0 ]; then
    inject "Refactor Move: updated Python imports in ${COUNT} files after moving ${OLD_PATH} → ${NEW_PATH}."
else
    inject "File moved from ${OLD_PATH} to ${NEW_PATH}. Found references but could not auto-update — check imports manually."
fi
exit 0

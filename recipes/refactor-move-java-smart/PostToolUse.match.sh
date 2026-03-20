#!/bin/bash
# Refactor Move Java — update package/import after mv
# Derives package name from directory structure (src/main/java/com/example → com.example)
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

# Detect: mv old.java new.java
OLD_PATH=$(echo "$MV_ARGS" | sed -n 's/^\([^[:space:]]\+\.java\)[[:space:]]\+.*/\1/p')
NEW_PATH=$(echo "$MV_ARGS" | sed -n 's/^[^[:space:]]\+[[:space:]]\+\([^[:space:]]\+\)/\1/p')
[ -z "$OLD_PATH" ] || [ -z "$NEW_PATH" ] && exit 1

if [ -d "$NEW_PATH" ]; then
    NEW_PATH="${NEW_PATH%/}/$(basename "$OLD_PATH")"
fi

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
MSG_UPDATED=$(sed -n 's/^updated:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_REFS=$(sed -n 's/^no_refs:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")

# Derive Java package from directory path
# Strips common source roots: src/main/java/, src/, app/src/main/java/
path_to_package() {
    echo "$1" | sed 's|^\./||' \
        | sed 's|^.*/src/main/java/||; s|^.*/src/test/java/||; s|^src/main/java/||; s|^src/test/java/||; s|^src/||' \
        | sed 's|/[^/]*\.java$||' \
        | sed 's|/|.|g'
}

OLD_PKG=$(path_to_package "$OLD_PATH")
NEW_PKG=$(path_to_package "$NEW_PATH")
[ -z "$OLD_PKG" ] || [ -z "$NEW_PKG" ] && exit 1
[ "$OLD_PKG" = "$NEW_PKG" ] && exit 1

OLD_CLASS=$(basename "$OLD_PATH" .java)
NEW_CLASS=$(basename "$NEW_PATH" .java)

# Escape dots for sed
OLD_PKG_ESC=$(echo "$OLD_PKG" | sed 's/\./\\./g')
NEW_PKG_ESC=$(echo "$NEW_PKG" | sed 's/\./\\./g')

# Update package declaration in moved file
if [ -f "$NEW_PATH" ]; then
    _hooker_sed_i "s|^package ${OLD_PKG_ESC};|package ${NEW_PKG};|" "$NEW_PATH" 2>/dev/null
fi

# If class was renamed too, update class declaration
if [ "$OLD_CLASS" != "$NEW_CLASS" ] && [ -f "$NEW_PATH" ]; then
    _hooker_sed_i "s|class ${OLD_CLASS}|class ${NEW_CLASS}|g" "$NEW_PATH" 2>/dev/null
fi

# Build old FQCN for import matching
OLD_FQCN="${OLD_PKG}.${OLD_CLASS}"
NEW_FQCN="${NEW_PKG}.${NEW_CLASS}"
OLD_FQCN_ESC=$(echo "$OLD_FQCN" | sed 's/\./\\./g')

# Find Java files importing old class
AFFECTED_FILES=$(grep -rl "import.*${OLD_PKG_ESC}\." --include='*.java' . 2>/dev/null \
    | grep -v '.git/' | grep -v '/build/' | grep -v '/target/' || true)

# Also search for wildcard imports of old package
WILDCARD_FILES=$(grep -rl "import.*${OLD_PKG_ESC}\.\*" --include='*.java' . 2>/dev/null \
    | grep -v '.git/' | grep -v '/build/' | grep -v '/target/' || true)

ALL_FILES=$(printf '%s\n%s' "$AFFECTED_FILES" "$WILDCARD_FILES" | sort -u)

[ -z "$ALL_FILES" ] && {
    inject "$MSG_NO_REFS"
    exit 0
}

COUNT=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    CHANGED=false

    # Replace specific import
    if grep -q "import[[:space:]]\+${OLD_FQCN_ESC}[[:space:]]*;" "$file" 2>/dev/null; then
        _hooker_sed_i "s|import ${OLD_FQCN_ESC};|import ${NEW_FQCN};|g" "$file" 2>/dev/null
        CHANGED=true
    fi

    # Replace wildcard import if package changed
    if [ "$OLD_PKG" != "$NEW_PKG" ] && grep -q "import[[:space:]]\+${OLD_PKG_ESC}\.\*;" "$file" 2>/dev/null; then
        # Don't change wildcard — other classes may still be in old package
        # Just add specific import for the moved class
        CHANGED=true
    fi

    # Replace fully qualified references in code
    if grep -q "${OLD_FQCN_ESC}" "$file" 2>/dev/null; then
        _hooker_sed_i "s|${OLD_FQCN_ESC}|${NEW_FQCN}|g" "$file" 2>/dev/null
        CHANGED=true
    fi

    $CHANGED && COUNT=$((COUNT + 1))
done <<< "$ALL_FILES"

if [ "$COUNT" -gt 0 ]; then
    MSG=$(echo "$MSG_UPDATED" | sed "s/{count}/$COUNT/g")
    inject "Refactor Move (Java): ${MSG}"
else
    inject "$MSG_NO_REFS"
fi
exit 0

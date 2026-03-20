#!/bin/bash
# Refactor Move C# — update namespace/using after mv
# Derives namespace from directory structure relative to .csproj location
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

# Detect: mv old.cs new.cs
OLD_PATH=$(echo "$MV_ARGS" | sed -n 's/^\([^[:space:]]\+\.cs\)[[:space:]]\+.*/\1/p')
NEW_PATH=$(echo "$MV_ARGS" | sed -n 's/^[^[:space:]]\+[[:space:]]\+\([^[:space:]]\+\)/\1/p')
[ -z "$OLD_PATH" ] || [ -z "$NEW_PATH" ] && exit 1

if [ -d "$NEW_PATH" ]; then
    NEW_PATH="${NEW_PATH%/}/$(basename "$OLD_PATH")"
fi

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
MSG_UPDATED=$(sed -n 's/^updated:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_REFS=$(sed -n 's/^no_refs:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")

# Find nearest .csproj to determine project root and root namespace
find_csproj_dir() {
    local DIR="$1"
    while [ "$DIR" != "." ] && [ "$DIR" != "/" ]; do
        ls "$DIR"/*.csproj 2>/dev/null | head -1 | grep -q . && echo "$DIR" && return
        DIR=$(dirname "$DIR")
    done
    # Fallback: current directory
    ls ./*.csproj 2>/dev/null | head -1 | grep -q . && echo "." && return
    return 1
}

# Derive namespace from path relative to .csproj
# Convention: directory structure = namespace (MyProject/Models/User.cs → MyProject.Models)
path_to_namespace() {
    local FILE_PATH="$1"
    local PROJ_DIR
    PROJ_DIR=$(find_csproj_dir "$(dirname "$FILE_PATH")")
    if [ -n "$PROJ_DIR" ]; then
        # Get root namespace from .csproj (RootNamespace element) or project dir name
        local ROOT_NS
        ROOT_NS=$(sed -n 's/.*<RootNamespace>\([^<]*\)<.*/\1/p' "$PROJ_DIR"/*.csproj 2>/dev/null | head -1)
        [ -z "$ROOT_NS" ] && ROOT_NS=$(basename "$PROJ_DIR")

        local REL
        REL=$(echo "$FILE_PATH" | sed "s|^${PROJ_DIR}/||; s|/[^/]*\.cs$||; s|/|.|g")
        if [ -n "$REL" ] && [ "$REL" != "$(basename "$FILE_PATH" .cs)" ]; then
            echo "${ROOT_NS}.${REL}"
        else
            echo "$ROOT_NS"
        fi
    else
        # No .csproj — derive from full path
        echo "$FILE_PATH" | sed 's|^\./||; s|/[^/]*\.cs$||; s|/|.|g'
    fi
}

OLD_NS=$(path_to_namespace "$OLD_PATH")
NEW_NS=$(path_to_namespace "$NEW_PATH")
[ -z "$OLD_NS" ] || [ -z "$NEW_NS" ] && exit 1
[ "$OLD_NS" = "$NEW_NS" ] && exit 1

OLD_CLASS=$(basename "$OLD_PATH" .cs)
NEW_CLASS=$(basename "$NEW_PATH" .cs)

OLD_NS_ESC=$(echo "$OLD_NS" | sed 's/\./\\./g')

# Update namespace in moved file (both block-scoped and file-scoped)
if [ -f "$NEW_PATH" ]; then
    _hooker_sed_i "s|^namespace ${OLD_NS_ESC}|namespace ${NEW_NS}|" "$NEW_PATH" 2>/dev/null
fi

# If class was renamed, update class declaration
if [ "$OLD_CLASS" != "$NEW_CLASS" ] && [ -f "$NEW_PATH" ]; then
    _hooker_sed_i "s|class ${OLD_CLASS}|class ${NEW_CLASS}|g" "$NEW_PATH" 2>/dev/null
fi

# Find C# files with using statements referencing old namespace
AFFECTED_FILES=$(grep -rl "using.*${OLD_NS_ESC}" --include='*.cs' . 2>/dev/null \
    | grep -v '.git/' | grep -v '/bin/' | grep -v '/obj/' || true)

# Also find fully qualified references
FQ_FILES=$(grep -rl "${OLD_NS_ESC}\.${OLD_CLASS}" --include='*.cs' . 2>/dev/null \
    | grep -v '.git/' | grep -v '/bin/' | grep -v '/obj/' || true)

ALL_FILES=$(printf '%s\n%s' "$AFFECTED_FILES" "$FQ_FILES" | sort -u)

[ -z "$ALL_FILES" ] && {
    inject "$MSG_NO_REFS"
    exit 0
}

COUNT=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    CHANGED=false

    # Replace using statements
    if grep -q "using[[:space:]]\+${OLD_NS_ESC};" "$file" 2>/dev/null; then
        _hooker_sed_i "s|using ${OLD_NS_ESC};|using ${NEW_NS};|g" "$file" 2>/dev/null
        CHANGED=true
    fi

    # Replace fully qualified references
    OLD_FQ="${OLD_NS}.${OLD_CLASS}"
    NEW_FQ="${NEW_NS}.${NEW_CLASS}"
    OLD_FQ_ESC=$(echo "$OLD_FQ" | sed 's/\./\\./g')
    if grep -q "${OLD_FQ_ESC}" "$file" 2>/dev/null; then
        _hooker_sed_i "s|${OLD_FQ_ESC}|${NEW_FQ}|g" "$file" 2>/dev/null
        CHANGED=true
    fi

    $CHANGED && COUNT=$((COUNT + 1))
done <<< "$ALL_FILES"

if [ "$COUNT" -gt 0 ]; then
    MSG=$(echo "$MSG_UPDATED" | sed "s/{count}/$COUNT/g")
    inject "Refactor Move (C#): ${MSG}"
else
    inject "$MSG_NO_REFS"
fi
exit 0

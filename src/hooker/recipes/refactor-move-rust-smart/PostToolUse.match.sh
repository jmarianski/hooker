#!/bin/bash
# Refactor Move Rust (smart) — update mod/use after mv
# PostToolUse hook: fires after Bash tool completes
# Updates `use crate::...` paths and warns about mod declarations.
source "${HOOKER_HELPERS}"

INPUT=$(cat)

TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" = "Bash" ] || exit 1

CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Strip leading env vars, cd chains, and mv flags
MV_CMD=$(echo "$CMD" | sed 's/^[^;|&]*&&[[:space:]]*//' | sed 's/^[A-Z_]*=[^[:space:]]*[[:space:]]*//')
MV_CMD=$(echo "$MV_CMD" | sed 's/^[A-Z_]*=[^[:space:]]*[[:space:]]*//')
MV_CMD=$(echo "$MV_CMD" | sed 's/^git[[:space:]]\+mv/mv/')
echo "$CMD" | grep -q 'HOOKER_NO_REFACTOR=1' && exit 1
MV_ARGS=$(echo "$MV_CMD" | sed 's/^mv[[:space:]]\+//; s/^-[a-zA-Z]\+[[:space:]]*//g; s/^--[a-zA-Z-]\+[[:space:]]*//g')

# Detect: mv old.rs new.rs or mv old.rs dir/
OLD_PATH=$(echo "$MV_ARGS" | sed -n 's/^\([^[:space:]]\+\.rs\)[[:space:]]\+.*/\1/p')
NEW_PATH=$(echo "$MV_ARGS" | sed -n 's/^[^[:space:]]\+[[:space:]]\+\([^[:space:]]\+\)/\1/p')
[ -z "$OLD_PATH" ] || [ -z "$NEW_PATH" ] && exit 1

# If moving to directory, append filename
if [ -d "$NEW_PATH" ]; then
    NEW_PATH="${NEW_PATH%/}/$(basename "$OLD_PATH")"
fi

# Must end in .rs
echo "$NEW_PATH" | grep -q '\.rs$' || exit 1

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load messages
MSG_UPDATED=$(sed -n 's/^updated:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_REFS=$(sed -n 's/^no_refs:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_CARGO=$(sed -n 's/^no_cargo:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")

# Find Cargo.toml (walk up)
find_cargo() {
    local dir="$1"
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        [ -f "$dir/Cargo.toml" ] && echo "$dir/Cargo.toml" && return 0
        dir=$(dirname "$dir")
    done
    return 1
}

CARGO_TOML=$(find_cargo "$(pwd)")
if [ -z "$CARGO_TOML" ]; then
    inject "$MSG_NO_CARGO"
    exit 0
fi
CRATE_ROOT=$(dirname "$CARGO_TOML")

# Convert file path to Rust module path
# src/foo/bar.rs → foo::bar
# src/foo/mod.rs → foo
path_to_mod() {
    local p="$1"
    # Remove crate root prefix and src/
    p=$(echo "$p" | sed "s|^${CRATE_ROOT}/||; s|^src/||; s|^lib/||")
    # Remove .rs extension
    p=$(echo "$p" | sed 's|\.rs$||')
    # Handle mod.rs → parent module
    p=$(echo "$p" | sed 's|/mod$||')
    # Convert / to ::
    echo "$p" | sed 's|/|::|g'
}

OLD_MOD=$(path_to_mod "$OLD_PATH")
NEW_MOD=$(path_to_mod "$NEW_PATH")

[ "$OLD_MOD" = "$NEW_MOD" ] && exit 1
[ -z "$OLD_MOD" ] || [ -z "$NEW_MOD" ] && exit 1

# Find all .rs files that might have use statements
AFFECTED_FILES=$(grep -rl "use.*${OLD_MOD}" --include='*.rs' "$CRATE_ROOT" 2>/dev/null | grep -v target/ || true)

# Also check for crate:: prefix variations
if [ -z "$AFFECTED_FILES" ]; then
    AFFECTED_FILES=$(grep -rl "crate::${OLD_MOD}" --include='*.rs' "$CRATE_ROOT" 2>/dev/null | grep -v target/ || true)
fi

COUNT=0
UPDATED_FILES=""

# Update use statements
if [ -n "$AFFECTED_FILES" ]; then
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        # Replace use crate::old_mod with use crate::new_mod
        # Also handle use super::old_mod, use self::old_mod
        if grep -q "${OLD_MOD}" "$file" 2>/dev/null; then
            _hooker_sed_i "s|crate::${OLD_MOD}|crate::${NEW_MOD}|g" "$file" 2>/dev/null
            _hooker_sed_i "s|super::${OLD_MOD}|super::${NEW_MOD}|g" "$file" 2>/dev/null
            _hooker_sed_i "s|self::${OLD_MOD}|self::${NEW_MOD}|g" "$file" 2>/dev/null
            COUNT=$((COUNT + 1))
            UPDATED_FILES="${UPDATED_FILES} $(basename "$file")"
        fi
    done <<< "$AFFECTED_FILES"
fi

# Check for mod declarations that need manual update
OLD_BASENAME=$(basename "$OLD_PATH" .rs)
NEW_BASENAME=$(basename "$NEW_PATH" .rs)
OLD_PARENT=$(dirname "$OLD_PATH")
NEW_PARENT=$(dirname "$NEW_PATH")

MOD_WARNING=""
if [ "$OLD_PARENT" != "$NEW_PARENT" ] || [ "$OLD_BASENAME" != "$NEW_BASENAME" ]; then
    if [ "$OLD_BASENAME" != "mod" ] && [ "$NEW_BASENAME" != "mod" ]; then
        MOD_WARNING=" Check mod declarations: may need to move 'mod ${OLD_BASENAME};' to new parent and rename to 'mod ${NEW_BASENAME};'."
    fi
fi

# Run cargo fmt if available
FMT_MSG=""
if command -v cargo >/dev/null 2>&1 && [ -f "$CARGO_TOML" ]; then
    (cd "$CRATE_ROOT" && cargo fmt 2>/dev/null) && FMT_MSG=" cargo fmt applied."
fi

if [ "$COUNT" -gt 0 ]; then
    MSG=$(echo "$MSG_UPDATED" | sed "s/{count}/$COUNT/g")
    inject "Refactor Move Rust: ${MSG} (${OLD_MOD} -> ${NEW_MOD}).${MOD_WARNING}${FMT_MSG}"
else
    inject "File moved: ${OLD_PATH} -> ${NEW_PATH}. ${MSG_NO_REFS}${MOD_WARNING}"
fi
exit 0

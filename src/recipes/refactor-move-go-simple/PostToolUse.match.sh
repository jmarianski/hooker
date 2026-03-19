#!/bin/bash
# Refactor Move (Go) — update imports after mv
source "${HOOKER_HELPERS}"

INPUT=$(cat)

TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" = "Bash" ] || exit 1

# Skip refactoring if explicitly disabled
[ "${HOOKER_NO_REFACTOR:-}" = "1" ] && exit 1

CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Detect: mv old.go new.go
OLD_PATH=$(echo "$CMD" | sed -n 's/^mv[[:space:]]\+\([^[:space:]]\+\.go\)[[:space:]]\+.*/\1/p')
NEW_PATH=$(echo "$CMD" | sed -n 's/^mv[[:space:]]\+[^[:space:]]\+[[:space:]]\+\([^[:space:]]\+\)/\1/p')
[ -z "$OLD_PATH" ] || [ -z "$NEW_PATH" ] && exit 1

if [ -d "$NEW_PATH" ]; then
    NEW_PATH="${NEW_PATH}/$(basename "$OLD_PATH")"
fi

# Get old and new directory (Go imports are by package/directory, not file)
OLD_DIR=$(dirname "$OLD_PATH")
NEW_DIR=$(dirname "$NEW_PATH")

# If same directory, no import changes needed (just a file rename)
[ "$OLD_DIR" = "$NEW_DIR" ] && exit 1

# Try to detect module path from go.mod
MOD_PATH=""
if [ -f "go.mod" ]; then
    MOD_PATH=$(sed -n 's/^module[[:space:]]\+\(.*\)/\1/p' go.mod | head -1)
fi

if [ -z "$MOD_PATH" ]; then
    inject "File moved from ${OLD_PATH} to ${NEW_PATH}. No go.mod found — cannot determine import paths. Check imports manually."
    exit 0
fi

# Build old and new import paths
OLD_IMPORT="${MOD_PATH}/${OLD_DIR}"
NEW_IMPORT="${MOD_PATH}/${NEW_DIR}"

# Clean up paths (remove ./ prefix, double slashes)
OLD_IMPORT=$(echo "$OLD_IMPORT" | sed 's|/\./|/|g; s|//|/|g; s|/$||')
NEW_IMPORT=$(echo "$NEW_IMPORT" | sed 's|/\./|/|g; s|//|/|g; s|/$||')

[ "$OLD_IMPORT" = "$NEW_IMPORT" ] && exit 1

# Find Go files importing old package
AFFECTED_FILES=$(grep -rl "\"${OLD_IMPORT}\"" --include='*.go' . 2>/dev/null | grep -v '.git/' || true)

[ -z "$AFFECTED_FILES" ] && {
    inject "File moved from ${OLD_PATH} to ${NEW_PATH}. No Go import references found for ${OLD_IMPORT}."
    exit 0
}

COUNT=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    if grep -q "\"${OLD_IMPORT}\"" "$file" 2>/dev/null; then
        sed -i "s|\"${OLD_IMPORT}\"|\"${NEW_IMPORT}\"|g" "$file" 2>/dev/null
        COUNT=$((COUNT + 1))
    fi
done <<< "$AFFECTED_FILES"

if [ "$COUNT" -gt 0 ]; then
    inject "Refactor Move: updated Go imports in ${COUNT} files (${OLD_IMPORT} → ${NEW_IMPORT})."
else
    inject "File moved from ${OLD_PATH} to ${NEW_PATH}. Found references but could not auto-update — check imports manually."
fi
exit 0

#!/bin/bash
# Hooker build script — regenerates dynamic sections in skills.
# Run after adding/changing recipes or modifying src/fragments.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
RECIPES_DIR="${ROOT_DIR}/recipes"

# --- Generate recipe catalog table ---
generate_recipe_catalog() {
    echo "| Recipe | Hook | Description |"
    echo "|--------|------|-------------|"
    for r in "${RECIPES_DIR}"/*/recipe.json; do
        [ -f "$r" ] || continue
        local dir
        dir=$(basename "$(dirname "$r")")
        local name
        name=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$r" | head -1)
        local desc
        desc=$(sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$r" | head -1)
        local hooks
        hooks=$(sed -n 's/.*"hooks".*\[\(.*\)\].*/\1/p' "$r" | tr -d '" ' | head -1)
        echo "| \`${dir}\` | ${hooks} | ${desc} |"
    done
}

# --- Generate uncovered hooks list ---
generate_uncovered_hooks() {
    local ALL_HOOKS="PermissionRequest PostToolUseFailure Notification SubagentStop TeammateIdle TaskCompleted InstructionsLoaded ConfigChange WorktreeCreate WorktreeRemove PreCompact PostCompact Elicitation ElicitationResult SessionEnd"
    local covered=""
    for r in "${RECIPES_DIR}"/*/recipe.json; do
        [ -f "$r" ] || continue
        covered="${covered} $(sed -n 's/.*"hooks".*\[\(.*\)\].*/\1/p' "$r" | tr -d '",')"
    done
    local uncovered=""
    for hook in $ALL_HOOKS; do
        if ! echo "$covered" | grep -q "$hook"; then
            [ -n "$uncovered" ] && uncovered="${uncovered}, "
            uncovered="${uncovered}${hook}"
        fi
    done
    echo "$uncovered"
}

# --- Inject into file between markers ---
# Usage: inject_section "file" "MARKER_NAME" "content"
inject_section() {
    local file="$1"
    local marker="$2"
    local content="$3"
    local start_marker="<!-- BUILD:${marker}:START -->"
    local end_marker="<!-- BUILD:${marker}:END -->"

    if ! grep -q "$start_marker" "$file" 2>/dev/null; then
        echo "  SKIP: no ${marker} markers in ${file}"
        return
    fi

    # Build replacement: markers + content
    local tmpfile
    tmpfile=$(mktemp)
    awk -v start="$start_marker" -v end="$end_marker" -v content="$content" '
        $0 ~ start { print; printf "%s\n", content; skip=1; next }
        $0 ~ end { skip=0 }
        !skip { print }
    ' "$file" > "$tmpfile"
    mv "$tmpfile" "$file"
    echo "  OK: ${marker} in ${file}"
}

# --- Main ---
echo "Building Hooker skills..."

CATALOG=$(generate_recipe_catalog)
UNCOVERED=$(generate_uncovered_hooks)
CATALOG_WITH_NOTE="${CATALOG}

**Hooks without recipes**: ${UNCOVERED}"

# Inject into recipe.md
inject_section "${ROOT_DIR}/commands/recipe.md" "RECIPE_CATALOG" "$CATALOG_WITH_NOTE"

echo "Done."

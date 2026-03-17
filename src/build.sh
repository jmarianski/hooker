#!/bin/bash
# Hooker build script — compiles src/commands/*.md → commands/*.md
# Processes BUILD markers, replacing dynamic sections with generated content.
# Static commands (without src/ source) are left untouched.
#
# Run: bash src/build.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
RECIPES_DIR="${ROOT_DIR}/recipes"
SRC_COMMANDS="${SCRIPT_DIR}/commands"
OUT_COMMANDS="${ROOT_DIR}/commands"

# --- Generators ---

generate_recipe_catalog() {
    echo "| Recipe | Hook | Description |"
    echo "|--------|------|-------------|"
    for r in "${RECIPES_DIR}"/*/recipe.json; do
        [ -f "$r" ] || continue
        local dir
        dir=$(basename "$(dirname "$r")")
        local desc
        desc=$(sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$r" | head -1)
        local hooks
        hooks=$(sed -n 's/.*"hooks".*\[\(.*\)\].*/\1/p' "$r" | tr -d '" ' | head -1)
        echo "| \`${dir}\` | ${hooks} | ${desc} |"
    done
}

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

# --- Process a single source file ---
# Copies src → out, replacing BUILD marker sections with generated content.
build_command() {
    local src="$1"
    local filename
    filename=$(basename "$src")
    local out="${OUT_COMMANDS}/${filename}"

    # Start with a copy of source
    cp "$src" "$out"

    # Process each BUILD marker found in the file
    local markers
    markers=$(grep -o '<!-- BUILD:[A-Z_]*:START -->' "$out" 2>/dev/null \
        | sed 's/<!-- BUILD://;s/:START -->//' || true)

    if [ -z "$markers" ]; then
        echo "  ${filename}: copied (no markers)"
        return
    fi

    for marker in $markers; do
        local content=""
        case "$marker" in
            RECIPE_CATALOG)
                local catalog
                catalog=$(generate_recipe_catalog)
                local uncovered
                uncovered=$(generate_uncovered_hooks)
                content="${catalog}

**Hooks without recipes**: ${uncovered}"
                ;;
            *)
                echo "  ${filename}: WARNING — unknown marker ${marker}, skipping"
                continue
                ;;
        esac

        # Replace content between markers
        local start_marker="<!-- BUILD:${marker}:START -->"
        local end_marker="<!-- BUILD:${marker}:END -->"
        local tmpfile
        tmpfile=$(mktemp)
        awk -v start="$start_marker" -v end="$end_marker" -v content="$content" '
            $0 ~ start { print; printf "%s\n", content; skip=1; next }
            $0 ~ end { skip=0 }
            !skip { print }
        ' "$out" > "$tmpfile"
        mv "$tmpfile" "$out"
        echo "  ${filename}: ${marker} ✓"
    done
}

# --- Main ---
echo "Building Hooker skills..."

# Process each source command
for src in "${SRC_COMMANDS}"/*.md; do
    [ -f "$src" ] || continue
    build_command "$src"
done

echo "Done."

#!/bin/bash
# Hooker build — compiles src/commands/*.md → commands/*.md
# Replaces {{ PLACEHOLDER }} with generated content.
# Static commands (without src/ source) are left untouched.
#
# Run: bash src/build.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
RECIPES_DIR="${ROOT_DIR}/recipes"

# --- Generators ---

recipe_catalog() {
    echo "| Recipe | Hook | Description |"
    echo "|--------|------|-------------|"
    for r in "${RECIPES_DIR}"/*/recipe.json; do
        [ -f "$r" ] || continue
        dir=$(basename "$(dirname "$r")")
        desc=$(sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$r" | head -1)
        hooks=$(sed -n 's/.*"hooks".*\[\(.*\)\].*/\1/p' "$r" | tr -d '" ' | head -1)
        echo "| \`${dir}\` | ${hooks} | ${desc} |"
    done
}

uncovered_hooks() {
    all="PermissionRequest PostToolUseFailure Notification SubagentStop TeammateIdle TaskCompleted InstructionsLoaded ConfigChange WorktreeCreate WorktreeRemove PreCompact PostCompact Elicitation ElicitationResult SessionEnd"
    covered=""
    for r in "${RECIPES_DIR}"/*/recipe.json; do
        [ -f "$r" ] || continue
        covered="${covered} $(sed -n 's/.*"hooks".*\[\(.*\)\].*/\1/p' "$r" | tr -d '",')"
    done
    out=""
    for hook in $all; do
        echo "$covered" | grep -q "$hook" || { [ -n "$out" ] && out="${out}, "; out="${out}${hook}"; }
    done
    echo "$out"
}

# --- Main ---
echo "Building skills..."

for src in "${SCRIPT_DIR}"/commands/*.md; do
    [ -f "$src" ] || continue
    name=$(basename "$src")
    out="${ROOT_DIR}/commands/${name}"

    # Check if file has any placeholders
    if ! grep -q '{{ *[A-Z_]* *}}' "$src" 2>/dev/null; then
        cp "$src" "$out"
        echo "  ${name}: copied"
        continue
    fi

    # Replace placeholders
    content=$(cat "$src")
    while IFS= read -r placeholder; do
        key=$(echo "$placeholder" | sed 's/.*{{ *//;s/ *}}.*//')
        case "$key" in
            RECIPE_CATALOG)  value=$(recipe_catalog) ;;
            UNCOVERED_HOOKS) value=$(uncovered_hooks) ;;
            *) echo "  ${name}: unknown {{ ${key} }}"; continue ;;
        esac
        # Replace placeholder with generated content (inline or full-line)
        content=$(echo "$content" | awk -v ph="$placeholder" -v val="$value" '
            index($0, ph) {
                # If line is just the placeholder, replace entirely
                line = $0
                gsub(/^[[:space:]]*/, "", line)
                gsub(/[[:space:]]*$/, "", line)
                if (line == ph) { print val }
                else { gsub(ph, val); print }
                next
            }
            { print }
        ')
    done < <(grep -o '{{ *[A-Z_]* *}}' "$src" | sort -u)

    echo "$content" > "$out"
    echo "  ${name}: built"
done

echo "Done."

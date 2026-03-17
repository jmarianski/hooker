#!/bin/bash
# Auto-format files after edit
# Adapted from ryanlewis/claude-format-hook (MIT)
source "${HOOKER_HELPERS}"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

case "$TOOL" in
    Edit|Write|NotebookEdit) ;;
    *) exit 1 ;;
esac

FILE=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 1

EXT="${FILE##*.}"

case "$EXT" in
    js|jsx|ts|tsx|css|scss|json|md|html|vue|svelte)
        if command -v prettier &>/dev/null; then
            prettier --write "$FILE" &>/dev/null
        elif command -v biome &>/dev/null; then
            biome format --write "$FILE" &>/dev/null
        fi
        ;;
    py)
        if command -v ruff &>/dev/null; then
            ruff format "$FILE" &>/dev/null
            ruff check --fix "$FILE" &>/dev/null
        elif command -v black &>/dev/null; then
            black -q "$FILE" &>/dev/null
        fi
        ;;
    go)
        command -v gofmt &>/dev/null && gofmt -w "$FILE" &>/dev/null
        ;;
    rs)
        command -v rustfmt &>/dev/null && rustfmt "$FILE" &>/dev/null
        ;;
    kt|kts)
        command -v ktlint &>/dev/null && ktlint -F "$FILE" &>/dev/null
        ;;
esac

# No output — silent formatting, don't interfere with hook response
exit 1

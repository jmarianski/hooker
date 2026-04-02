#!/bin/bash
# Cache Catcher — UserPromptSubmit interceptor
# Catches "cache-catcher <cmd>" prompts, runs CLI, blocks with output.
# Zero API cost — prompt never reaches Claude.

INPUT=$(cat)

# Extract prompt field from hook JSON
PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Only match "cache-catcher" prefix
case "$PROMPT" in
    cache-catcher\ *|cache-catcher) ;;
    *) exit 0 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="${SCRIPT_DIR}/scripts/cache-catcher.sh"

# Parse subcommand + args
CMD=$(echo "$PROMPT" | sed 's/^cache-catcher[[:space:]]*//')
[ -z "$CMD" ] && CMD="status"

# Run CLI, capture output (strip ANSI for clean block message)
OUTPUT=$(bash "$CLI" $CMD 2>&1 | sed 's/\x1b\[[0-9;]*m//g')

if [ -z "$OUTPUT" ]; then
    OUTPUT="cache-catcher: no output for '$CMD'"
fi

# Block prompt — show output to user, don't send to Claude
ESCAPED=$(printf '%s' "$OUTPUT" | awk '{
    gsub(/\\/, "\\\\")
    gsub(/"/, "\\\"")
    gsub(/\t/, "\\t")
    gsub(/\r/, "\\r")
    printf "%s", (NR>1 ? "\\n" : "") $0
}')

echo "{\"decision\": \"block\", \"reason\": \"${ESCAPED}\"}"

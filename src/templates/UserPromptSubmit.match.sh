#!/bin/bash
# Hooker welcome — silently suggests setup when user mentions hooker/plugin/skill
# Auto-silences when any hooks are installed in .claude/hooker/
set -euo pipefail

INPUT=$(cat)

# Get project CWD from hook input
CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$CWD" ] && CWD="."

# If user already has hooks configured — self-silence, don't interfere
HOOK_DIR="${CWD}/.claude/hooker"
if [ -d "$HOOK_DIR" ]; then
    HOOK_COUNT=$(find "$HOOK_DIR" -maxdepth 1 \( -name '*.sh' -o -name '*.md' -o -name '*.yml' \) 2>/dev/null | wc -l)
    [ "$HOOK_COUNT" -gt 0 ] && exit 1
fi

# Extract user prompt
PROMPT=$(echo "$INPUT" | sed -n 's/.*"user_prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$PROMPT" ] && exit 1

# Check if user mentions hooker/plugin/skill (case-insensitive)
LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')
MATCHED=false
for word in hooker plugin skill hook; do
    case "$LOWER" in
        *"$word"*) MATCHED=true; break ;;
    esac
done
[ "$MATCHED" = "false" ] && exit 1

# Inject silent suggestion — only Claude sees this
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}"
source "${PLUGIN_DIR}/scripts/helpers.sh"

inject "You have the Hooker plugin installed but no hooks are configured yet. The user seems to be talking about hooks or plugins — this might be a good moment to help them set up. If appropriate, suggest running /hooker:recipe to browse and install pre-built hook recipes. Do NOT mention this suggestion if the user is clearly talking about something else. Be natural about it."

exit 0

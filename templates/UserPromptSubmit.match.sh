#!/bin/bash
# Hook Discovery (template) — detects when user might want hook/automation.
# This is a plugin template copy of the hook-discovery recipe.
# Install the recipe for customizable keywords and messages.
# Session cooldown: fires once per tier per session to avoid spamming.

INPUT=$(cat)

PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$PROMPT" ] && exit 1

SESSION_ID=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$SESSION_ID" ] && exit 1

PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}"
MSGS_FILE="${PLUGIN_DIR}/recipes/hook-discovery/messages.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1
}

LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# --- Tier 1: Direct hook keywords ---
TIER1=false
IFS=',' read -ra T1_ARRAY <<< "$(yml_get tier1_words)"
for word in "${T1_ARRAY[@]}"; do
    word=$(echo "$word" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$LOWER" in
        *"$word"*) TIER1=true; break ;;
    esac
done

# --- Tier 2: Peripheral — automation/event intent ---
TIER2=false
if [ "$TIER1" = "false" ]; then
    IFS=',' read -ra T2_ARRAY <<< "$(yml_get tier2_words)"
    for word in "${T2_ARRAY[@]}"; do
        word=$(echo "$word" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$LOWER" in
            *"$word"*) TIER2=true; break ;;
        esac
    done

    if [ "$TIER2" = "false" ]; then
        TIER2_PATTERNS=$(yml_get tier2_patterns)
        echo "$LOWER" | grep -qiE "$TIER2_PATTERNS" && TIER2=true
    fi
fi

[ "$TIER1" = "false" ] && [ "$TIER2" = "false" ] && exit 1

# --- Session cooldown: once per tier per session ---
COOLDOWN_DIR="/tmp/hooker_discovery"
mkdir -p "$COOLDOWN_DIR" 2>/dev/null
TIER_TAG="tier1"
[ "$TIER2" = "true" ] && TIER_TAG="tier2"
COOLDOWN_FILE="${COOLDOWN_DIR}/${SESSION_ID}_${TIER_TAG}"
[ -f "$COOLDOWN_FILE" ] && exit 1
touch "$COOLDOWN_FILE" 2>/dev/null

# --- Inject ---
source "${PLUGIN_DIR}/scripts/helpers.sh"

if [ "$TIER1" = "true" ]; then
    inject "$(yml_get tier1_message)"
else
    inject "$(yml_get tier2_message)"
fi

exit 0

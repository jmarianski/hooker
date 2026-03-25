#!/bin/bash
# Hook Discovery — detects when user might want hook/automation functionality.
# Injects context-aware suggestion (hidden from user, Claude decides whether to act).
# Session cooldown: fires once per tier per session to avoid spamming.
source "${HOOKER_HELPERS}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSGS_FILE=".claude/hooker/hook-discovery.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

INPUT=$(cat)

PROMPT=$(echo "$INPUT" | _hooker_json_field "prompt")
[ -z "$PROMPT" ] && exit 1

SESSION_ID=$(echo "$INPUT" | _hooker_json_field "session_id")
[ -z "$SESSION_ID" ] && exit 1

LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# --- Load keywords from messages.yml ---
yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1
}

TIER1_WORDS=$(yml_get tier1_words)
TIER2_WORDS=$(yml_get tier2_words)
TIER2_PATTERNS=$(yml_get tier2_patterns)

# --- Tier 1: Direct hook keywords ---
TIER1=false
IFS=',' read -ra T1_ARRAY <<< "$TIER1_WORDS"
for word in "${T1_ARRAY[@]}"; do
    word=$(echo "$word" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$LOWER" in
        *"$word"*) TIER1=true; break ;;
    esac
done

# --- Tier 2: Peripheral — automation/event intent ---
TIER2=false
if [ "$TIER1" = "false" ]; then
    IFS=',' read -ra T2_ARRAY <<< "$TIER2_WORDS"
    for word in "${T2_ARRAY[@]}"; do
        word=$(echo "$word" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$LOWER" in
            *"$word"*) TIER2=true; break ;;
        esac
    done
    # Regex patterns
    if [ "$TIER2" = "false" ] && [ -n "$TIER2_PATTERNS" ]; then
        echo "$LOWER" | grep -qiE "$TIER2_PATTERNS" && TIER2=true
    fi
fi

# Nothing matched
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
if [ "$TIER1" = "true" ]; then
    MSG=$(yml_get tier1_message)
else
    MSG=$(yml_get tier2_message)
fi

inject "$MSG"
exit 0

#!/bin/bash
# Hooker UserPromptSubmit template — two jobs:
# 1. Overflow hooks: add plugin hooks that CC's hooks.json validation rejects (version-gated)
# 2. Hook discovery: suggest /hooker:recipe when user mentions hooks/automation keywords

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$SESSION_ID" ] && exit 1

PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}"
COOLDOWN_DIR="/tmp/hooker_discovery"
mkdir -p "$COOLDOWN_DIR" 2>/dev/null

# =============================================================================
# 1. OVERFLOW HOOKS — run once per session, patch settings.json if needed
# =============================================================================
OVERFLOW_DONE="${COOLDOWN_DIR}/${SESSION_ID}_overflow"
if [ ! -f "$OVERFLOW_DONE" ]; then
    touch "$OVERFLOW_DONE" 2>/dev/null

    OVERFLOW_CONF="${PLUGIN_DIR}/recipes/hook-discovery/overflow_hooks.conf"
    SETTINGS_FILE="${HOME}/.claude/settings.json"

    if [ -f "$OVERFLOW_CONF" ]; then
        # Detect CC version from binary path
        CC_VERSION=$(readlink -f "$(which claude 2>/dev/null)" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

        if [ -n "$CC_VERSION" ]; then
            # Version comparison: returns 0 if $1 >= $2
            _ver_gte() {
                [ "$(printf '%s\n%s' "$1" "$2" | sort -V | head -1)" = "$2" ]
            }

            INJECT_CMD="${PLUGIN_DIR}/scripts/inject.sh"
            NEEDS_PATCH=false

            while IFS='=' read -r MIN_VER HOOKS_CSV; do
                # Skip comments and empty lines
                case "$MIN_VER" in \#*|"") continue ;; esac
                [ -z "$HOOKS_CSV" ] && continue

                if _ver_gte "$CC_VERSION" "$MIN_VER"; then
                    IFS=',' read -ra HOOK_NAMES <<< "$HOOKS_CSV"
                    for HOOK_NAME in "${HOOK_NAMES[@]}"; do
                        HOOK_NAME=$(echo "$HOOK_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        [ -z "$HOOK_NAME" ] && continue

                        # Check if already in settings.json
                        if [ -f "$SETTINGS_FILE" ] && grep -q "\"${HOOK_NAME}\"" "$SETTINGS_FILE" 2>/dev/null; then
                            continue
                        fi

                        NEEDS_PATCH=true

                        # Ensure settings.json exists with hooks object
                        if [ ! -f "$SETTINGS_FILE" ]; then
                            mkdir -p "$(dirname "$SETTINGS_FILE")"
                            echo '{"hooks":{}}' > "$SETTINGS_FILE"
                        fi

                        # Add hook entry via python3 (safe JSON manipulation)
                        if command -v python3 >/dev/null 2>&1; then
                            python3 -c "
import json, sys
try:
    with open('$SETTINGS_FILE') as f:
        data = json.load(f)
except:
    data = {}
hooks = data.setdefault('hooks', {})
if '$HOOK_NAME' not in hooks:
    hooks['$HOOK_NAME'] = [{'matcher': '', 'hooks': [{'type': 'command', 'command': '$INJECT_CMD'}]}]
    with open('$SETTINGS_FILE', 'w') as f:
        json.dump(data, f, indent=2)
    print('added', file=sys.stderr)
" 2>/dev/null
                        fi
                    done
                fi
            done < "$OVERFLOW_CONF"
        fi
    fi
fi

# =============================================================================
# 2. HOOK DISCOVERY — suggest /hooker:recipe on keyword match
# =============================================================================
PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$PROMPT" ] && exit 1

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

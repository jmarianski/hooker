#!/bin/bash
# Cache Catcher — UserPromptSubmit interceptor
# Catches "cache-catcher <cmd>" and optional extra prefixes from config (prompt_aliases).
# Zero API cost — prompt never reaches Claude.

INPUT=$(cat)

# Extract fields from hook JSON
PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
HOOK_CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${HOOK_CWD:-$(pwd)}}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yml"
if [ -f "${PROJECT_DIR}/.claude/cache-catcher.config.yml" ]; then
    CONFIG_FILE="${PROJECT_DIR}/.claude/cache-catcher.config.yml"
fi

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/[[:space:]]*#.*$//;s/[[:space:]]*$//' | sed 's/^"\(.*\)"$/\1/' || true
}

# Resolve command prefix: cache-catcher always, then comma-separated prompt_aliases
PREFIX=""
case "$PROMPT" in
    cache-catcher|cache-catcher\ *) PREFIX=cache-catcher ;;
    *)
        ALIASES_RAW=$(yml_get prompt_aliases)
        OLD_IFS=$IFS
        IFS=','
        for _a in $ALIASES_RAW; do
            _a=$(echo "$_a" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -z "$_a" ] && continue
            case "$PROMPT" in
                "${_a}"|"${_a}"\ *)
                    PREFIX=$_a
                    break
                    ;;
            esac
        done
        IFS=$OLD_IFS
        ;;
esac

[ -z "$PREFIX" ] && exit 0

CLI="${SCRIPT_DIR}/scripts/cache-catcher.sh"

if [ "$PROMPT" = "$PREFIX" ]; then
    CMD=""
else
    CMD="${PROMPT#"${PREFIX}"}"
    CMD=$(echo "$CMD" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

# Run CLI, capture output (strip ANSI for clean block message)
# CACHE_CATCHER_FROM_CLAUDE_CODE: watch must not run here (infinite loop / no TTY)
ESC=$(printf '\033')
OUTPUT=$(CACHE_CATCHER_FROM_CLAUDE_CODE=1 bash "$CLI" -p "$PROJECT_DIR" $CMD 2>&1 | sed "s/${ESC}\[[0-9;]*m//g")

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

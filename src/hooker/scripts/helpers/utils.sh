# Portable sed-in-place. macOS sed requires '' after -i, GNU sed does not.
_hooker_sed_i() {
    if [ "$(uname)" = "Darwin" ]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Reverse lines of a file. Portable replacement for tac.
_hooker_reverse() {
    awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}'
}

# Get last assistant turn from transcript. Filters noise (progress, hook_progress),
# stops at real user prompt (not tool_result).
# Real user prompts have "type":"user" WITHOUT "sourceToolAssistantUUID" on the same line.
# Usage: _hooker_last_turn "$TRANSCRIPT_PATH"
_hooker_last_turn() {
    local TRANSCRIPT="$1"
    [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && return 1
    # Note: || true prevents SIGPIPE (141) when awk exits early and breaks the pipe.
    # Without it, set -o pipefail in callers treats SIGPIPE as failure.
    awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}' "$TRANSCRIPT" \
        | grep -v '"type":"progress"' | grep -v '"type":"hook_progress"' \
        | awk '/"type":"user"/ && !/sourceToolAssistantUUID/{exit} {print}' || true
}

# Get last N assistant turns from transcript. Filters noise (progress, hook_progress),
# stops after N real user prompts (not tool_result).
# Usage: _hooker_last_turns "$TRANSCRIPT_PATH" [N]
# N defaults to 1 (same as _hooker_last_turn). Use N=2 for last 2 turns, etc.
_hooker_last_turns() {
    local TRANSCRIPT="$1"
    local N="${2:-1}"
    [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && return 1
    [ "$N" -lt 1 ] 2>/dev/null && N=1
    # Reverse, filter noise, stop after N user prompts (turn boundaries)
    awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}' "$TRANSCRIPT" \
        | grep -v '"type":"progress"' | grep -v '"type":"hook_progress"' \
        | awk -v n="$N" '
            /"type":"user"/ && !/sourceToolAssistantUUID/ { count++ }
            count > n { exit }
            { print }
        ' || true
}

# Strip <hidden> tags from a string, return visible part only.
# Handles both single-line (<hidden>...</hidden> on one line) and multiline.
_hooker_strip_hidden() {
    echo "$1" | sed 's/<hidden>[^<]*<\/hidden>//g' | awk '
    /<hidden>/ { skip=1; next }
    /<\/hidden>/ { skip=0; next }
    !skip { print }
    '
}

_hooker_resolve_codex_home() {
    if [ -n "${HOOKER_CODEX_HOME:-}" ]; then
        echo "$HOOKER_CODEX_HOME"
        return
    fi

    if [ -n "${CODEX_HOME:-}" ]; then
        echo "$CODEX_HOME"
        return
    fi

    case "${HOOKER_PLUGIN_DIR:-${CLAUDE_PLUGIN_ROOT:-}}" in
        */plugins/cache/*)
            echo "${HOOKER_PLUGIN_DIR%%/plugins/cache/*}"
            return
            ;;
    esac

    echo "${HOME}/.codex"
}

_hooker_project_hook_dir() {
    if [ "${HOOKER_HOST:-unknown}" = "codex" ]; then
        echo "${HOOKER_CWD:-.}/.codex/hooker"
    else
        echo "${HOOKER_CWD:-.}/.claude/hooker"
    fi
}

_hooker_legacy_project_hook_dir() {
    echo "${HOOKER_CWD:-.}/.claude/hooker"
}

_hooker_user_hook_dir() {
    if [ "${HOOKER_HOST:-unknown}" = "codex" ]; then
        echo "$(_hooker_resolve_codex_home)/hooker"
    else
        echo "${HOME}/.claude/hooker"
    fi
}

_hooker_legacy_user_hook_dir() {
    echo "${HOME}/.claude/hooker"
}

_hooker_project_hook_config() {
    if [ "${HOOKER_HOST:-unknown}" = "codex" ]; then
        echo "${HOOKER_CWD:-.}/.codex/hooker.json"
    else
        echo "${HOOKER_CWD:-.}/.claude/hooker.json"
    fi
}

_hooker_legacy_project_hook_config() {
    echo "${HOOKER_CWD:-.}/.claude/hooker.json"
}

#!/bin/bash
# Hooker - Universal Hook Injection Framework
# Reads hook event from stdin, finds matching template, injects content.
# Cross-platform: works on Linux, macOS, and Windows (Git Bash).

set -euo pipefail

# --- Parse arguments ---
# Usage: inject.sh                         (default: dispatch by hook event)
#        inject.sh --recipe path/to/Hook   (recipe mode: path = recipe dir + hook name)
RECIPE_PATH=""
while [ $# -gt 0 ]; do
    case "$1" in
        --recipe) RECIPE_PATH="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Read input JSON from stdin
INPUT=$(cat)

# Determine hook event — from --recipe path or stdin JSON
if [ -n "$RECIPE_PATH" ]; then
    HOOK_EVENT=$(basename "$RECIPE_PATH")
    RECIPE_DIR=$(dirname "$RECIPE_PATH")
else
    HOOK_EVENT=$(echo "$INPUT" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    RECIPE_DIR=""
fi

if [ -z "$HOOK_EVENT" ]; then
    exit 0
fi

# --- Export env vars for match scripts ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-${HOOKER_PLUGIN_DIR:-${SCRIPT_DIR}/..}}"
if [ -f "${PLUGIN_DIR}/.codex-plugin/plugin.json" ]; then
    HOOKER_HOST="${HOOKER_HOST:-codex}"
elif [ -f "${PLUGIN_DIR}/.claude-plugin/plugin.json" ]; then
    HOOKER_HOST="${HOOKER_HOST:-claude}"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    HOOKER_HOST="${HOOKER_HOST:-claude}"
else
    HOOKER_HOST="${HOOKER_HOST:-unknown}"
fi
export HOOKER_PLUGIN_DIR="$PLUGIN_DIR"
export HOOKER_HOST
export HOOKER_HELPERS="${PLUGIN_DIR}/scripts/helpers.sh"
export HOOKER_EVENT="$HOOK_EVENT"

# Multi-language helper paths (Python, JS/TS can import these)
export HOOKER_HELPERS_PY="${PLUGIN_DIR}/helpers/hooker_helpers.py"
export HOOKER_HELPERS_JS="${PLUGIN_DIR}/helpers/hooker_helpers.js"
# Allow `from hooker_helpers import ...` / `require('hooker_helpers')`
export PYTHONPATH="${PLUGIN_DIR}/helpers${PYTHONPATH:+:$PYTHONPATH}"
export NODE_PATH="${PLUGIN_DIR}/helpers${NODE_PATH:+:$NODE_PATH}"
HOOKER_CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
export HOOKER_CWD
HOOKER_TRANSCRIPT=$(echo "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
export HOOKER_TRANSCRIPT
HOOKER_PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-${HOOKER_CWD:-$(pwd)}}"
export HOOKER_PROJECT_ROOT
# Claude-only convenience path used by a few recipes that inspect Claude's
# internal per-project storage. Codex does not expose an equivalent location.
HOOKER_PROJECT_SLUG=$(echo "$HOOKER_CWD" | sed 's|/|-|g; s|^-||')
HOOKER_PROJECT_DIR="${HOOKER_PROJECT_ROOT}"
HOOKER_CLAUDE_PROJECT_DIR=""
HOOKER_CODEX_HOME="${CODEX_HOME:-}"
if [ -z "$HOOKER_CODEX_HOME" ] && [ "$HOOKER_HOST" = "codex" ]; then
    case "$PLUGIN_DIR" in
        */plugins/cache/*)
            HOOKER_CODEX_HOME="${PLUGIN_DIR%%/plugins/cache/*}"
            ;;
    esac
fi
if [ -z "$HOOKER_CODEX_HOME" ] && [ "$HOOKER_HOST" = "codex" ]; then
    HOOKER_CODEX_HOME="${HOME}/.codex"
fi
if [ "$HOOKER_HOST" = "claude" ] && [ -n "$HOOKER_PROJECT_SLUG" ]; then
    HOOKER_CLAUDE_PROJECT_DIR="${HOME}/.claude/projects/-${HOOKER_PROJECT_SLUG}"
    HOOKER_PROJECT_DIR="${HOOKER_CLAUDE_PROJECT_DIR}"
fi
export HOOKER_PROJECT_SLUG HOOKER_PROJECT_DIR HOOKER_CLAUDE_PROJECT_DIR HOOKER_CODEX_HOME

# Shared helper functions include runtime/path resolution used below.
# shellcheck disable=SC1090
. "${PLUGIN_DIR}/scripts/helpers.sh"
HOOKER_PROJECT_HOOK_DIR=$(_hooker_project_hook_dir)
HOOKER_USER_HOOK_DIR=$(_hooker_user_hook_dir)
export HOOKER_PROJECT_HOOK_DIR HOOKER_USER_HOOK_DIR

# --- Logging ---
HOOKER_CONFIG=$(_hooker_project_hook_config)
[ -f "$HOOKER_CONFIG" ] || HOOKER_CONFIG=$(_hooker_legacy_project_hook_config)
LOGGING_ENABLED="${HOOKER_LOG:-0}"
if [ -f "$HOOKER_CONFIG" ]; then
    grep -q '"logs"[[:space:]]*:[[:space:]]*true' "$HOOKER_CONFIG" 2>/dev/null && LOGGING_ENABLED="1"
fi

log() {
    [ "$LOGGING_ENABLED" = "0" ] && return
    LOG_FILE="${HOME}/.cache/hooker/hooker.log"
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$HOOK_EVENT] $*" >> "$LOG_FILE"
}

log "Hook triggered in $(pwd) host=${HOOKER_HOST}${RECIPE_DIR:+ (recipe: $RECIPE_DIR)}"

# --- Runtime resolution for multi-language match scripts ---
# @bundle helpers/runtime.sh

# --- Find template and/or match script ---
# Match scripts can be in any language: Hook.match.sh, Hook.match.py, Hook.match.js, etc.
# With --recipe path/Hook: look only in that directory
# Without --recipe: priority: project > user global > plugin default
# Standalone match scripts (no .md) are allowed — they handle everything via output
PROJECT_DIR="$(_hooker_project_hook_dir)"
LEGACY_PROJECT_DIR="$(_hooker_legacy_project_hook_dir)"
USER_DIR="$(_hooker_user_hook_dir)"
LEGACY_USER_DIR="$(_hooker_legacy_user_hook_dir)"

TEMPLATE_FILE=""
MATCH_SCRIPT=""

if [ -n "$RECIPE_DIR" ]; then
    # Recipe mode — look in recipe directory only
    if [ -f "${RECIPE_DIR}/${HOOK_EVENT}.md" ]; then
        TEMPLATE_FILE="${RECIPE_DIR}/${HOOK_EVENT}.md"
        log "Using recipe template: ${TEMPLATE_FILE}"
    fi
    MATCH_SCRIPT=$(_hooker_find_match "$RECIPE_DIR" "$HOOK_EVENT" 2>/dev/null) || true
    [ -n "$MATCH_SCRIPT" ] && log "Using recipe match script: ${MATCH_SCRIPT}"
else
    # Default mode — check project first, then user global, then plugin defaults
    for DIR in "$PROJECT_DIR" "$USER_DIR" "$LEGACY_PROJECT_DIR" "$LEGACY_USER_DIR" "${PLUGIN_DIR}/templates"; do
        if [ -f "${DIR}/${HOOK_EVENT}.md" ] && [ -z "$TEMPLATE_FILE" ]; then
            TEMPLATE_FILE="${DIR}/${HOOK_EVENT}.md"
            log "Using template: ${TEMPLATE_FILE}"
        fi
        if [ -z "$MATCH_SCRIPT" ]; then
            MATCH_SCRIPT=$(_hooker_find_match "$DIR" "$HOOK_EVENT" 2>/dev/null) || true
            [ -n "$MATCH_SCRIPT" ] && log "Using match script: ${MATCH_SCRIPT}"
        fi
    done
fi

if [ -z "$TEMPLATE_FILE" ] && [ -z "$MATCH_SCRIPT" ]; then
    log "No template or match script found, skipping"
    exit 0
fi

# --- Run match script ---
# Match scripts can:
#   exit 0 (no output)  → matched, fall through to template
#   exit 0 (with output)→ matched, output IS the response (template ignored)
#   exit 1 (no output)  → no match, skip silently
#   exit 2+ (any)       → error/crash, log and warn agent
if [ -n "$MATCH_SCRIPT" ]; then
    MATCH_EXT="${MATCH_SCRIPT##*.}"
    MATCH_RUNTIME=$(_hooker_resolve_runtime "$MATCH_EXT")
    log "Running match script: $MATCH_SCRIPT (ext=$MATCH_EXT, runtime=${MATCH_RUNTIME:-direct})"
    MATCH_STDERR=$(mktemp 2>/dev/null || echo "/tmp/hooker_stderr_$$")
    set +e
    MATCH_OUTPUT=$(echo "$INPUT" | _hooker_run_match "$MATCH_SCRIPT" 2>"$MATCH_STDERR")
    MATCH_EXIT=$?
    set -e
    MATCH_ERR=$(cat "$MATCH_STDERR" 2>/dev/null)
    rm -f "$MATCH_STDERR" 2>/dev/null

    if [ "$MATCH_EXIT" -eq 1 ]; then
        log "Match script: no match, skipping"
        exit 0
    elif [ "$MATCH_EXIT" -gt 1 ]; then
        log "Match script ERROR (exit $MATCH_EXIT): $MATCH_ERR"
        # Inform agent about the crash — use inject (hidden from user)
        SCRIPT_NAME=$(basename "$MATCH_SCRIPT")
        cat <<CRASH_EOF
</local-command-stdout>

Hooker: match script ${SCRIPT_NAME} crashed (exit ${MATCH_EXIT}). ${MATCH_ERR:+Error: $MATCH_ERR. }Check dependencies and logs (~/.cache/hooker/hooker.log).

<local-command-stdout>
CRASH_EOF
        exit 0
    fi
    log "Match script: MATCHED"
    if [ -n "$MATCH_OUTPUT" ]; then
        log "Match script returned output, using as direct response"
        echo "$MATCH_OUTPUT"
        exit 0
    fi
fi

# If we only had a match script (no template), and it matched but had no output — nothing to do
if [ -z "$TEMPLATE_FILE" ]; then
    log "Match script matched but no output and no template, skipping"
    exit 0
fi

# --- Parse frontmatter ---
ACTION="inject"
CONTENT=""

if head -1 "$TEMPLATE_FILE" | grep -q '^---$'; then
    ACTION=$(awk '/^---$/{n++; next} n==1 && /^type:/{gsub(/^type:[[:space:]]*/, ""); print; exit}' "$TEMPLATE_FILE")
    CONTENT=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$TEMPLATE_FILE")
else
    CONTENT=$(cat "$TEMPLATE_FILE")
fi

[ -z "$ACTION" ] && ACTION="inject"

# Trim leading/trailing whitespace from content
CONTENT=$(echo "$CONTENT" | sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba;}')

if [ -z "$CONTENT" ]; then
    log "Template empty, skipping"
    exit 0
fi

log "Action: $ACTION"

# --- Helper: escape content for JSON (portable, no python3) ---
json_escape() {
    awk '
    BEGIN { ORS=""; first=1 }
    {
        if (!first) printf "\\n"
        first=0
        gsub(/\\/, "\\\\")
        gsub(/"/, "\\\"")
        gsub(/\t/, "\\t")
        gsub(/\r/, "\\r")
        print
    }
    END { }
    ' | { IFS= read -r -d '' x || true; printf '"%s"' "$x"; }
}

# --- Helper: split visible/hidden content and output ---
# <visible>text</visible> → shown in terminal
# everything else → hidden via XML trick (only Claude sees)
output_with_visibility() {
    local TEXT="$1"

    if echo "$TEXT" | grep -q '<visible>'; then
        # Has <visible> sections — extract and split
        local VISIBLE=""
        local HIDDEN=""

        # Extract visible parts (awk, no perl dependency)
        VISIBLE=$(echo "$TEXT" | awk '
            /<visible>/ {
                sub(/.*<visible>/, "")
                p=1
            }
            /<\/visible>/ {
                sub(/<\/visible>.*/, "")
                if (p) print
                p=0
                next
            }
            p { print }
        ')

        # Extract hidden parts (everything outside <visible> tags)
        HIDDEN=$(echo "$TEXT" | awk '
            /<visible>/ { sub(/<visible>.*/, ""); if (length) print; skip=1; next }
            /<\/visible>/ { skip=0; sub(/.*<\/visible>/, ""); if (length) print; next }
            !skip { print }
        ')
        HIDDEN=$(echo "$HIDDEN" | sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba;}')

        # Output visible part normally (user sees it)
        [ -n "$VISIBLE" ] && echo "$VISIBLE"

        # Output hidden part via XML trick (only Claude sees)
        if [ -n "$HIDDEN" ]; then
            cat <<HIDDEN_EOF
</local-command-stdout>

${HIDDEN}

<local-command-stdout>
HIDDEN_EOF
        fi
    else
        # No visible sections — hide everything
        cat <<INJECT_EOF
</local-command-stdout>

${TEXT}

<local-command-stdout>
INJECT_EOF
    fi
}

# --- Execute action ---
case "$ACTION" in
    inject)
        output_with_visibility "$CONTENT"
        log "Injected context"
        ;;

    remind)
        # Block stop with visible reminder (loop-safe).
        # Content is always fully visible — XML trick doesn't work inside
        # JSON reason strings (Claude Code renders them as plaintext).
        if echo "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
            log "Stop hook already active, allowing"
            exit 0
        fi
        ESCAPED=$(echo "$CONTENT" | json_escape)
        echo "{\"decision\": \"block\", \"reason\": ${ESCAPED}}"
        log "Blocked stop with reminder"
        ;;

    block)
        ESCAPED=$(echo "$CONTENT" | json_escape)
        echo "{\"decision\": \"block\", \"reason\": ${ESCAPED}}"
        log "Blocked"
        ;;

    allow)
        ESCAPED=$(echo "$CONTENT" | json_escape)
        echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"allow\", \"permissionDecisionReason\": ${ESCAPED}}}"
        log "Allowed"
        ;;

    deny)
        ESCAPED=$(echo "$CONTENT" | json_escape)
        echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": ${ESCAPED}}}"
        log "Denied"
        ;;

    warn)
        # Warn but don't block — inject as system message visible to Claude
        ESCAPED=$(echo "$CONTENT" | json_escape)
        echo "{\"hookSpecificOutput\": {\"hookEventName\": \"${HOOK_EVENT}\", \"systemMessage\": ${ESCAPED}}}"
        log "Warned"
        ;;

    ask)
        # Escalate to user for manual decision (PreToolUse only)
        ESCAPED=$(echo "$CONTENT" | json_escape)
        echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"ask\", \"permissionDecisionReason\": ${ESCAPED}}}"
        log "Escalated to user"
        ;;

    context)
        ESCAPED=$(echo "$CONTENT" | json_escape)
        echo "{\"additionalContext\": ${ESCAPED}}"
        log "Added additional context"
        ;;

    *)
        log "Unknown action: $ACTION, treating as inject"
        cat <<INJECT_EOF
</local-command-stdout>

${CONTENT}

<local-command-stdout>
INJECT_EOF
        ;;
esac

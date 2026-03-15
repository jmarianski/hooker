#!/bin/bash
# Hooker - Universal Hook Injection Framework
# Reads hook event from stdin, finds matching template, injects content.

set -euo pipefail

# Read input JSON from stdin
INPUT=$(cat)

# Extract hook event name (no jq dependency)
HOOK_EVENT=$(echo "$INPUT" | grep -oP '"hook_event_name"\s*:\s*"\K[^"]+' || true)

if [ -z "$HOOK_EVENT" ]; then
    exit 0
fi

# --- Logging ---
HOOKER_CONFIG=".claude/hooker.json"
LOGGING_ENABLED="${HOOKER_LOG:-0}"
if [ -f "$HOOKER_CONFIG" ]; then
    grep -q '"logs"\s*:\s*true' "$HOOKER_CONFIG" 2>/dev/null && LOGGING_ENABLED="1"
fi

log() {
    [ "$LOGGING_ENABLED" = "0" ] && return
    LOG_FILE="${HOME}/.cache/hooker/hooker.log"
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$HOOK_EVENT] $*" >> "$LOG_FILE"
}

log "Hook triggered in $(pwd)"

# --- Find template ---
# Priority: project override > plugin default
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}"
WORKSPACE_DIR=".claude/hooker"

TEMPLATE_FILE=""
MATCH_SCRIPT=""

if [ -f "${WORKSPACE_DIR}/${HOOK_EVENT}.md" ]; then
    TEMPLATE_FILE="${WORKSPACE_DIR}/${HOOK_EVENT}.md"
    # Match script: same dir, .match.sh extension
    [ -x "${WORKSPACE_DIR}/${HOOK_EVENT}.match.sh" ] && MATCH_SCRIPT="${WORKSPACE_DIR}/${HOOK_EVENT}.match.sh"
    log "Using workspace template: $(pwd)/${TEMPLATE_FILE}"
elif [ -f "${PLUGIN_DIR}/templates/${HOOK_EVENT}.md" ]; then
    TEMPLATE_FILE="${PLUGIN_DIR}/templates/${HOOK_EVENT}.md"
    [ -x "${PLUGIN_DIR}/templates/${HOOK_EVENT}.match.sh" ] && MATCH_SCRIPT="${PLUGIN_DIR}/templates/${HOOK_EVENT}.match.sh"
    log "Using plugin template: ${TEMPLATE_FILE}"
fi

if [ -z "$TEMPLATE_FILE" ]; then
    log "No template found, skipping"
    exit 0
fi

# --- Run match script ---
if [ -n "$MATCH_SCRIPT" ]; then
    log "Running match script: $MATCH_SCRIPT"
    if echo "$INPUT" | "$MATCH_SCRIPT" 2>/dev/null; then
        log "Match script: MATCHED"
    else
        log "Match script: no match, skipping"
        exit 0
    fi
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

# --- Helper: escape content for JSON ---
json_escape() {
    python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null \
        || printf '"%s"' "$(echo "$1" | sed 's/"/\\"/g' | tr '\n' ' ')"
}

# --- Execute action ---
case "$ACTION" in
    inject)
        cat <<INJECT_EOF
</local-command-stdout>

${CONTENT}

<local-command-stdout>
INJECT_EOF
        log "Injected context"
        ;;

    remind)
        # Block stop to remind, but prevent infinite loop via stop_hook_active
        if echo "$INPUT" | grep -qP '"stop_hook_active"\s*:\s*true'; then
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

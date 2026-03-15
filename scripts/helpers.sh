#!/bin/bash
# Hooker — helper functions for match scripts
# Source this in your match script: source "${HOOKER_HELPERS}"
# Then use: warn "message", deny "reason", allow, block "reason", etc.
#
# Visibility:
#   JSON helpers (warn, deny, block...) are VISIBLE by default.
#   Use <hidden>...</hidden> tags to hide parts from user (only Claude sees them).
#   Use load_md "file.md" to load a file as hidden content.

# --- Internal helpers ---

_hooker_json_escape() {
    python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null \
        || printf '"%s"' "$(echo "$1" | sed 's/"/\\"/g' | tr '\n' ' ')"
}

# Extract <hidden> content from a string
_hooker_extract_hidden() {
    perl -0777 -ne 'while(/<hidden>(.*?)<\/hidden>/gs){print "$1\n"}' 2>/dev/null <<< "$1"
}

# Strip <hidden> tags from a string, return visible part
_hooker_strip_hidden() {
    perl -0777 -pe 's/\s*<hidden>.*?<\/hidden>\s*//gs' 2>/dev/null <<< "$1"
}

# Split message into hidden (XML trick) and visible (clean) parts.
# Sets global vars: _HOOKER_HIDDEN, _HOOKER_CLEAN
# Called directly (not in subshell!) to preserve variables.
_hooker_process_hidden() {
    local MSG="$1"
    local HIDDEN=$(_hooker_extract_hidden "$MSG")
    _HOOKER_CLEAN=$(_hooker_strip_hidden "$MSG")

    if [ -n "$HIDDEN" ]; then
        _HOOKER_HIDDEN="</local-command-stdout>

${HIDDEN}

<local-command-stdout>"
    else
        _HOOKER_HIDDEN=""
    fi
}

# --- Public helpers ---

warn() {
    _hooker_process_hidden "$1"
    [ -n "$_HOOKER_HIDDEN" ] && echo "$_HOOKER_HIDDEN"
    local ESCAPED=$(echo "$_HOOKER_CLEAN" | _hooker_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"${HOOKER_EVENT}\", \"systemMessage\": ${ESCAPED}}}"
}

deny() {
    _hooker_process_hidden "${1:-Denied by Hooker}"
    [ -n "$_HOOKER_HIDDEN" ] && echo "$_HOOKER_HIDDEN"
    local ESCAPED=$(echo "$_HOOKER_CLEAN" | _hooker_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": ${ESCAPED}}}"
}

allow() {
    _hooker_process_hidden "${1:-Allowed by Hooker}"
    [ -n "$_HOOKER_HIDDEN" ] && echo "$_HOOKER_HIDDEN"
    local ESCAPED=$(echo "$_HOOKER_CLEAN" | _hooker_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"allow\", \"permissionDecisionReason\": ${ESCAPED}}}"
}

ask() {
    _hooker_process_hidden "${1:-Hooker requests confirmation}"
    [ -n "$_HOOKER_HIDDEN" ] && echo "$_HOOKER_HIDDEN"
    local ESCAPED=$(echo "$_HOOKER_CLEAN" | _hooker_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"ask\", \"permissionDecisionReason\": ${ESCAPED}}}"
}

block() {
    _hooker_process_hidden "${1:-Blocked by Hooker}"
    [ -n "$_HOOKER_HIDDEN" ] && echo "$_HOOKER_HIDDEN"
    local ESCAPED=$(echo "$_HOOKER_CLEAN" | _hooker_json_escape)
    echo "{\"decision\": \"block\", \"reason\": ${ESCAPED}}"
}

remind() {
    _hooker_process_hidden "$1"
    [ -n "$_HOOKER_HIDDEN" ] && echo "$_HOOKER_HIDDEN"
    local ESCAPED=$(echo "$_HOOKER_CLEAN" | _hooker_json_escape)
    echo "{\"decision\": \"block\", \"reason\": ${ESCAPED}}"
}

inject() {
    cat <<INJECT_EOF
</local-command-stdout>

$1

<local-command-stdout>
INJECT_EOF
}

visible() {
    echo "$1"
}

context() {
    _hooker_process_hidden "$1"
    [ -n "$_HOOKER_HIDDEN" ] && echo "$_HOOKER_HIDDEN"
    local ESCAPED=$(echo "$_HOOKER_CLEAN" | _hooker_json_escape)
    echo "{\"additionalContext\": ${ESCAPED}}"
}

# --- File loaders ---

# Load a .md file as hidden content (Claude sees it, user doesn't)
# Looks in: .claude/hooker/ → plugin templates/
load_md() {
    local FILE=""
    for DIR in ".claude/hooker" "${CLAUDE_PLUGIN_ROOT:-}/templates"; do
        if [ -f "${DIR}/$1" ]; then
            FILE="${DIR}/$1"
            break
        fi
    done
    [ -z "$FILE" ] && return
    echo "<hidden>$(cat "$FILE")</hidden>"
}

# Load a .md file as visible content
load_md_visible() {
    local FILE=""
    for DIR in ".claude/hooker" "${CLAUDE_PLUGIN_ROOT:-}/templates"; do
        if [ -f "${DIR}/$1" ]; then
            FILE="${DIR}/$1"
            break
        fi
    done
    [ -z "$FILE" ] && return
    cat "$FILE"
}

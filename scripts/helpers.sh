#!/bin/bash
# Hooker — helper functions for match scripts
# Source this in your match script: source "${HOOKER_HELPERS}"
# Then use: warn "message", deny "reason", allow, block "reason", etc.
#
# Visibility:
#   inject() — hidden from user by default (XML trick). Use <visible> tags to show parts.
#   JSON helpers (warn, deny, block, remind, allow, ask) — ALWAYS VISIBLE to user.
#     <hidden> tags are stripped but content is NOT hidden (Claude Code renders
#     JSON reason/message as plaintext — XML trick cannot escape JSON strings).
#   load_md "file.md" — only useful inside inject(), not inside JSON helpers.

# --- Internal helpers ---

_hooker_json_escape() {
    python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null \
        || printf '"%s"' "$(echo "$1" | sed 's/"/\\"/g' | tr '\n' ' ')"
}

# Strip <hidden> tags from a string, return visible part only.
# Used by JSON helpers — hidden content is discarded because Claude Code
# renders JSON reason/message as plaintext (XML trick doesn't work there).
_hooker_strip_hidden() {
    perl -0777 -pe 's/\s*<hidden>.*?<\/hidden>\s*//gs' 2>/dev/null <<< "$1"
}

# --- Public helpers ---

warn() {
    # <hidden> tags are stripped — JSON responses are always fully visible
    local CLEAN=$(_hooker_strip_hidden "$1")
    local ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"${HOOKER_EVENT}\", \"systemMessage\": ${ESCAPED}}}"
}

deny() {
    local CLEAN=$(_hooker_strip_hidden "${1:-Denied by Hooker}")
    local ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": ${ESCAPED}}}"
}

allow() {
    local CLEAN=$(_hooker_strip_hidden "${1:-Allowed by Hooker}")
    local ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"allow\", \"permissionDecisionReason\": ${ESCAPED}}}"
}

ask() {
    local CLEAN=$(_hooker_strip_hidden "${1:-Hooker requests confirmation}")
    local ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"ask\", \"permissionDecisionReason\": ${ESCAPED}}}"
}

block() {
    local CLEAN=$(_hooker_strip_hidden "${1:-Blocked by Hooker}")
    local ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
    echo "{\"decision\": \"block\", \"reason\": ${ESCAPED}}"
}

remind() {
    local CLEAN=$(_hooker_strip_hidden "$1")
    local ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
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
    local CLEAN=$(_hooker_strip_hidden "$1")
    local ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
    echo "{\"additionalContext\": ${ESCAPED}}"
}

# --- File loaders ---

# Load a .md file content.
# Only useful inside inject() — JSON helpers (block, deny, etc.) are always visible.
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
    cat "$FILE"
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

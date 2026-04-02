# JSON response helpers — all ALWAYS VISIBLE to user.
# <hidden> tags are stripped but content is NOT hidden.

warn() {
    local CLEAN
    CLEAN=$(_hooker_strip_hidden "$1")
    local ESCAPED
    ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"${HOOKER_EVENT}\", \"systemMessage\": ${ESCAPED}}}"
}

deny() {
    local CLEAN
    CLEAN=$(_hooker_strip_hidden "${1:-Denied by Hooker}")
    local ESCAPED
    ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": ${ESCAPED}}}"
}

allow() {
    local CLEAN
    CLEAN=$(_hooker_strip_hidden "${1:-Allowed by Hooker}")
    local ESCAPED
    ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"allow\", \"permissionDecisionReason\": ${ESCAPED}}}"
}

ask() {
    local CLEAN
    CLEAN=$(_hooker_strip_hidden "${1:-Hooker requests confirmation}")
    local ESCAPED
    ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"ask\", \"permissionDecisionReason\": ${ESCAPED}}}"
}

block() {
    local CLEAN
    CLEAN=$(_hooker_strip_hidden "${1:-Blocked by Hooker}")
    local ESCAPED
    ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
    echo "{\"decision\": \"block\", \"reason\": ${ESCAPED}}"
}

remind() {
    local CLEAN
    CLEAN=$(_hooker_strip_hidden "$1")
    local ESCAPED
    ESCAPED=$(echo "$CLEAN" | _hooker_json_escape)
    echo "{\"decision\": \"block\", \"reason\": ${ESCAPED}}"
}

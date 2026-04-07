# File loaders.
# Only useful inside inject() — JSON helpers (block, deny, etc.) are always visible.
# Looks in: .claude/hooker/ → ~/.claude/hooker/ → plugin templates/

load_md() {
    local FILE=""
    for DIR in ".claude/hooker" "${HOME}/.claude/hooker" "${HOOKER_PLUGIN_DIR:-${CLAUDE_PLUGIN_ROOT:-}}/templates"; do
        if [ -f "${DIR}/$1" ]; then
            FILE="${DIR}/$1"
            break
        fi
    done
    [ -z "$FILE" ] && return
    cat "$FILE"
}

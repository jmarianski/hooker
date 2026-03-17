# File loaders.
# Only useful inside inject() — JSON helpers (block, deny, etc.) are always visible.

# Load a .md file content.
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

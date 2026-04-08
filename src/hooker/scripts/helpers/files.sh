# File loaders.
# Only useful inside inject() — JSON helpers (block, deny, etc.) are always visible.
# Claude: .claude/hooker/ → ~/.claude/hooker/ → plugin templates/
# Codex: .codex/hooker/ → ${CODEX_HOME}/hooker/ → legacy .claude fallbacks → plugin templates/

load_md() {
    local FILE=""
    for DIR in \
        "$(_hooker_project_hook_dir)" \
        "$(_hooker_user_hook_dir)" \
        "$(_hooker_legacy_project_hook_dir)" \
        "$(_hooker_legacy_user_hook_dir)" \
        "${HOOKER_PLUGIN_DIR:-${CLAUDE_PLUGIN_ROOT:-}}/templates"
    do
        if [ -f "${DIR}/$1" ]; then
            FILE="${DIR}/$1"
            break
        fi
    done
    [ -z "$FILE" ] && return
    cat "$FILE"
}

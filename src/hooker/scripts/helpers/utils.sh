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

# Strip <hidden> tags from a string, return visible part only.
# Handles both single-line (<hidden>...</hidden> on one line) and multiline.
_hooker_strip_hidden() {
    echo "$1" | sed 's/<hidden>[^<]*<\/hidden>//g' | awk '
    /<hidden>/ { skip=1; next }
    /<\/hidden>/ { skip=0; next }
    !skip { print }
    '
}

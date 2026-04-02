#!/bin/bash
# Detect lazy code patterns after edit
# Adapted from claudekit (MIT)
source "${HOOKER_HELPERS}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSGS_FILE=".claude/hooker/detect-lazy-code.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1 || echo "$2"
}

INPUT=$(cat)
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

case "$TOOL" in
    Edit|Write) ;;
    *) exit 1 ;;
esac

FILE=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 1

# Check for comment-replaced code
if grep -q '//[[:space:]]*\.\.\.[[:space:]]*\(rest\|remaining\|other\|existing\|previous\|same\)' "$FILE" 2>/dev/null; then
    MSG=$(yml_get rest_of_slash "Lazy code detected in {file}: found '// ... rest of' pattern. Write the actual implementation.")
    MSG="${MSG//\{file\}/$FILE}"
    warn "$MSG"
    exit 0
fi

if grep -q '#[[:space:]]*\.\.\.[[:space:]]*\(rest\|remaining\|other\|existing\|previous\|same\)' "$FILE" 2>/dev/null; then
    MSG=$(yml_get rest_of_hash "Lazy code detected in {file}: found '# ... rest of' pattern. Write the actual implementation.")
    MSG="${MSG//\{file\}/$FILE}"
    warn "$MSG"
    exit 0
fi

# Check for placeholder comments
if grep -q '\(TODO\|FIXME\|HACK\):[[:space:]]*\(implement\|add\|fix\|handle\)[[:space:]]\+\(this\|here\|later\)' "$FILE" 2>/dev/null; then
    MSG=$(yml_get placeholder "Placeholder detected in {file}: vague TODO/FIXME. Be specific or implement it now.")
    MSG="${MSG//\{file\}/$FILE}"
    warn "$MSG"
    exit 0
fi

exit 1

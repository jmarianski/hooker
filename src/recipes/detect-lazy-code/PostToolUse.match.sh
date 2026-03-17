#!/bin/bash
# Detect lazy code patterns after edit
# Adapted from claudekit (MIT)
source "${HOOKER_HELPERS}"

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
    warn "Lazy code detected in ${FILE}: found '// ... rest of' pattern. Write the actual implementation."
    exit 0
fi

if grep -q '#[[:space:]]*\.\.\.[[:space:]]*\(rest\|remaining\|other\|existing\|previous\|same\)' "$FILE" 2>/dev/null; then
    warn "Lazy code detected in ${FILE}: found '# ... rest of' pattern. Write the actual implementation."
    exit 0
fi

# Check for placeholder comments
if grep -q '\(TODO\|FIXME\|HACK\):[[:space:]]*\(implement\|add\|fix\|handle\)[[:space:]]\+\(this\|here\|later\)' "$FILE" 2>/dev/null; then
    warn "Placeholder detected in ${FILE}: vague TODO/FIXME. Be specific or implement it now."
    exit 0
fi

exit 1

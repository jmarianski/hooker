#!/bin/bash
# Detect lazy code patterns after edit
# Adapted from claudekit (MIT)
source "${HOOKER_HELPERS}"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"\K[^"]+' || true)

case "$TOOL" in
    Edit|Write) ;;
    *) exit 1 ;;
esac

FILE=$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"\K[^"]+' || true)
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 1

# Check for comment-replaced code
if grep -qP '//\s*\.{3}\s*(rest|remaining|other|existing|previous|same)' "$FILE" 2>/dev/null; then
    warn "Lazy code detected in ${FILE}: found '// ... rest of' pattern. Write the actual implementation."
    exit 0
fi

if grep -qP '#\s*\.{3}\s*(rest|remaining|other|existing|previous|same)' "$FILE" 2>/dev/null; then
    warn "Lazy code detected in ${FILE}: found '# ... rest of' pattern. Write the actual implementation."
    exit 0
fi

# Check for placeholder comments
if grep -qP '(TODO|FIXME|HACK):\s*(implement|add|fix|handle)\s+(this|here|later)' "$FILE" 2>/dev/null; then
    warn "Placeholder detected in ${FILE}: vague TODO/FIXME. Be specific or implement it now."
    exit 0
fi

exit 1

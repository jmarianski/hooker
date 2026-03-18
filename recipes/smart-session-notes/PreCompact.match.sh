#!/bin/bash
# Smart Session Notes — create filtered markdown notes before compaction
source "${HOOKER_HELPERS}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE=".claude/hooker/smart-session-notes.config.yml"
[ -f "$CONFIG_FILE" ] || CONFIG_FILE="${SCRIPT_DIR}/config.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$CONFIG_FILE" 2>/dev/null | head -1 || echo "$2"
}

# Read config
INCLUDE_USER="$(yml_get include_user_messages true)"
INCLUDE_ASSISTANT="$(yml_get include_assistant_text true)"
INCLUDE_ERRORS="$(yml_get include_errors true)"
INCLUDE_TOOL_CALLS="$(yml_get include_tool_calls false)"
INCLUDE_TOOL_RESULTS="$(yml_get include_tool_results false)"
OUTPUT="$(yml_get output .claude/hooker/session-notes.md)"

# Need transcript
[ -z "${HOOKER_TRANSCRIPT:-}" ] && exit 1
[ -f "${HOOKER_TRANSCRIPT}" ] || exit 1

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT")" 2>/dev/null

# Generate timestamp
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown')"

# Write header
cat > "$OUTPUT" <<HEADER_EOF
# Session Notes (pre-compaction backup)
# Generated: ${TIMESTAMP}
HEADER_EOF

NEED_SEP=0

# Process JSONL transcript line by line
while IFS= read -r LINE; do
    [ -z "$LINE" ] && continue

    # Extract type — first occurrence only
    TYPE="$(echo "$LINE" | sed -n 's/.*"type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

    case "$TYPE" in
        user)
            [ "$INCLUDE_USER" = "true" ] || continue
            # User messages have "content": "text" (string, not array)
            TEXT="$(echo "$LINE" | sed -n 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
            [ -z "$TEXT" ] && continue
            # Unescape basic JSON escapes
            TEXT="$(printf '%b' "$TEXT")"
            if [ "$NEED_SEP" -eq 1 ]; then
                printf '\n---\n' >> "$OUTPUT"
            fi
            printf '\n## User\n%s\n' "$TEXT" >> "$OUTPUT"
            NEED_SEP=1
            ;;
        assistant)
            [ "$INCLUDE_ASSISTANT" = "true" ] || continue
            # Assistant messages have "content": [{"type": "text", "text": "..."}]
            # Extract text field value (may contain escaped chars)
            TEXT="$(echo "$LINE" | sed -n 's/.*"type"[[:space:]]*:[[:space:]]*"text"[^}]*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
            [ -z "$TEXT" ] && continue
            TEXT="$(printf '%b' "$TEXT")"
            printf '\n## Assistant\n%s\n' "$TEXT" >> "$OUTPUT"
            NEED_SEP=1
            ;;
        tool_result)
            if [ "$INCLUDE_ERRORS" = "true" ]; then
                STDERR="$(echo "$LINE" | sed -n 's/.*"stderr"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
                if [ -n "$STDERR" ]; then
                    STDERR="$(printf '%b' "$STDERR")"
                    printf '\n## Error\n%s\n' "$STDERR" >> "$OUTPUT"
                    NEED_SEP=1
                fi
            fi
            if [ "$INCLUDE_TOOL_RESULTS" = "true" ]; then
                STDOUT="$(echo "$LINE" | sed -n 's/.*"stdout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
                if [ -n "$STDOUT" ]; then
                    printf '\n## Tool Result\n%s\n' "$STDOUT" >> "$OUTPUT"
                    NEED_SEP=1
                fi
            fi
            ;;
        tool_use)
            [ "$INCLUDE_TOOL_CALLS" = "true" ] || continue
            TOOL_NAME="$(echo "$LINE" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
            [ -z "$TOOL_NAME" ] && continue
            printf '\n## Tool Call: %s\n' "$TOOL_NAME" >> "$OUTPUT"
            NEED_SEP=1
            ;;
    esac
done < "${HOOKER_TRANSCRIPT}"

inject "Session notes saved to ${OUTPUT} before compaction."
exit 0

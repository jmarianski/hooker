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
OUTPUT_DIR="$(dirname "$OUTPUT")"
mkdir -p "$OUTPUT_DIR" 2>/dev/null

# Generate timestamp
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'unknown')"

# Write header
cat > "$OUTPUT" <<HEADER_EOF
# Session Notes (pre-compaction backup)
# Generated: ${TIMESTAMP}
HEADER_EOF

# Track whether we wrote a separator before this exchange
NEED_SEP=0

# Process JSONL transcript line by line
while IFS= read -r LINE; do
    [ -z "$LINE" ] && continue

    # Extract top-level type field
    TYPE="$(echo "$LINE" | sed -n 's/.*"type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

    case "$TYPE" in
        user)
            [ "$INCLUDE_USER" = "true" ] || continue
            # Extract text content from message.content[].text
            TEXT="$(echo "$LINE" | sed -n 's/.*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
            [ -z "$TEXT" ] && continue
            if [ "$NEED_SEP" -eq 1 ]; then
                printf '\n---\n' >> "$OUTPUT"
            fi
            printf '\n## User\n%s\n' "$TEXT" >> "$OUTPUT"
            NEED_SEP=1
            ;;
        assistant)
            [ "$INCLUDE_ASSISTANT" = "true" ] || continue
            TEXT="$(echo "$LINE" | sed -n 's/.*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
            [ -z "$TEXT" ] && continue
            printf '\n## Assistant\n%s\n' "$TEXT" >> "$OUTPUT"
            NEED_SEP=1
            ;;
        tool_result)
            [ "$INCLUDE_ERRORS" = "true" ] || continue
            # Check for stderr content
            STDERR="$(echo "$LINE" | sed -n 's/.*"stderr"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
            [ -z "$STDERR" ] && continue
            printf '\n## Error\n%s\n' "$STDERR" >> "$OUTPUT"
            NEED_SEP=1
            ;;
        tool_use)
            [ "$INCLUDE_TOOL_CALLS" = "true" ] || continue
            TOOL_NAME="$(echo "$LINE" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
            [ -z "$TOOL_NAME" ] && continue
            printf '\n## Tool Call: %s\n' "$TOOL_NAME" >> "$OUTPUT"
            NEED_SEP=1
            ;;
    esac

    # Handle tool_results with include_tool_results
    if [ "$TYPE" = "tool_result" ] && [ "$INCLUDE_TOOL_RESULTS" = "true" ]; then
        STDOUT="$(echo "$LINE" | sed -n 's/.*"stdout"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
        [ -n "$STDOUT" ] && {
            printf '\n## Tool Result\n%s\n' "$STDOUT" >> "$OUTPUT"
            NEED_SEP=1
        }
    fi

done < "${HOOKER_TRANSCRIPT}"

inject "Session notes saved to ${OUTPUT} before compaction. The file contains a filtered markdown summary of the session transcript."
exit 0

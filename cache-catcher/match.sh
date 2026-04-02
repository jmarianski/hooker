#!/bin/bash
# Cache Catcher — detect broken prompt caching from transcript usage data
# Standalone plugin version — no hooker dependency
# Helpers are inlined at build time by src/build.go

# --- Inline helpers (warn, deny, json extraction) ---
# These functions are minimal copies; build.go can optionally inline
# the full helpers.sh bundle, but we keep it lean for standalone.

_cc_json_field() {
    sed -n "s/.*\"${1}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

_cc_json_number() {
    sed -n "s/.*\"${1}\"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p" | head -1
}

_cc_json_escape() {
    awk '{
        gsub(/\\/, "\\\\")
        gsub(/"/, "\\\"")
        gsub(/\t/, "\\t")
        gsub(/\r/, "\\r")
        printf "%s", (NR>1 ? "\\n" : "") $0
    }'
}

_cc_warn() {
    local ESCAPED
    ESCAPED=$(printf '%s' "$1" | _cc_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PostToolUse\", \"systemMessage\": \"${ESCAPED}\"}}"
}

_cc_deny() {
    local ESCAPED
    ESCAPED=$(printf '%s' "$1" | _cc_json_escape)
    echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": \"${ESCAPED}\"}}"
}

# --- Config ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yml"

# Project-level override
if [ -f ".claude/cache-catcher.config.yml" ]; then
    CONFIG_FILE=".claude/cache-catcher.config.yml"
fi

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$CONFIG_FILE" 2>/dev/null | head -1 || echo "$2"
}

MSGS_FILE="${SCRIPT_DIR}/messages.yml"
if [ -f ".claude/cache-catcher.messages.yml" ]; then
    MSGS_FILE=".claude/cache-catcher.messages.yml"
fi

msg_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1 || echo "$2"
}

# Read config
MODE="$(yml_get mode warn)"
LOOKBACK="$(yml_get lookback 3)"
THRESHOLD="$(yml_get threshold 1.0)"
MIN_TOKENS="$(yml_get min_tokens 5000)"
STREAK="$(yml_get streak 1)"
COOLDOWN="$(yml_get cooldown 60)"
IGNORE_FIRST="$(yml_get ignore_first_turn true)"

# --- Read CC hook JSON from stdin ---
INPUT=$(cat)

TRANSCRIPT=$(echo "$INPUT" | _cc_json_field transcript_path)
SESSION_ID=$(echo "$INPUT" | _cc_json_field session_id)

[ -z "$TRANSCRIPT" ] && exit 0
[ -f "$TRANSCRIPT" ] || exit 0

# --- Cooldown ---
STATE_DIR="/tmp/cache-catcher"
mkdir -p "$STATE_DIR" 2>/dev/null
STATE_FILE="${STATE_DIR}/${SESSION_ID}.state"

if [ -f "$STATE_FILE" ]; then
    LAST_WARN=$(sed -n 's/^last_warn:[[:space:]]*//p' "$STATE_FILE" 2>/dev/null | head -1)
    if [ -n "$LAST_WARN" ]; then
        NOW=$(date +%s 2>/dev/null || echo 0)
        ELAPSED=$((NOW - LAST_WARN))
        [ "$ELAPSED" -lt "$COOLDOWN" ] 2>/dev/null && exit 0
    fi
fi

# --- Resume detection: skip first few turns after resume ---
RESUME_FILE="${STATE_DIR}/${SESSION_ID}.resumed"
if [ -f "$RESUME_FILE" ]; then
    # Count PostToolUse calls since resume (use resume file mtime vs now)
    RESUME_AGE=$(( $(date +%s) - $(stat -c %Y "$RESUME_FILE" 2>/dev/null || stat -f %m "$RESUME_FILE" 2>/dev/null || echo 0) ))
    if [ "$RESUME_AGE" -lt 30 ] 2>/dev/null; then
        # Within 30s of resume — skip (cache is rebuilding)
        exit 0
    fi
    # Resume grace period expired, remove marker
    rm -f "$RESUME_FILE" 2>/dev/null
fi

# --- Extract cache metrics from recent assistant turns ---
USAGE_DATA=$(grep '"type":"assistant"' "$TRANSCRIPT" | \
    grep '"usage"' | \
    tail -n "$LOOKBACK")

[ -z "$USAGE_DATA" ] && exit 0

TOTAL_TURNS=$(grep -c '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null || echo 0)
if [ "$IGNORE_FIRST" = "true" ] && [ "$TOTAL_TURNS" -le 1 ]; then
    exit 0
fi

# Parse turns into tmp file
TMP_FILE="${STATE_DIR}/${SESSION_ID}.tmp"

SKIP_FIRST=0
if [ "$IGNORE_FIRST" = "true" ]; then
    FIRST_OFFSET=$((TOTAL_TURNS - LOOKBACK))
    [ "$FIRST_OFFSET" -le 0 ] && SKIP_FIRST=1
fi

AFTER_RESUME=0
echo "$USAGE_DATA" | while IFS= read -r LINE; do
    [ -z "$LINE" ] && continue
    CREATION=$(echo "$LINE" | _cc_json_number cache_creation_input_tokens)
    READ=$(echo "$LINE" | _cc_json_number cache_read_input_tokens)
    CREATION="${CREATION:-0}"
    READ="${READ:-0}"

    if [ "$SKIP_FIRST" -eq 1 ]; then
        SKIP_FIRST=0
        continue
    fi

    # Resume detection: skip empty turns (boundary) and next turn (cache rebuild)
    if [ "$CREATION" -eq 0 ] 2>/dev/null && [ "$READ" -eq 0 ] 2>/dev/null; then
        AFTER_RESUME=1
        continue
    fi
    if [ "$AFTER_RESUME" -eq 1 ]; then
        AFTER_RESUME=0
        continue
    fi

    echo "${CREATION}:${READ}"
done > "$TMP_FILE" 2>/dev/null

# --- Analyze ---
BAD_COUNT=0
TOTAL_CREATION=0
TOTAL_READ=0
TURN_COUNT=0

while IFS=: read -r C R; do
    [ -z "$C" ] && continue
    TURN_COUNT=$((TURN_COUNT + 1))
    TOTAL_CREATION=$((TOTAL_CREATION + C))
    TOTAL_READ=$((TOTAL_READ + R))

    [ "$C" -lt "$MIN_TOKENS" ] 2>/dev/null && continue

    if [ "$R" -eq 0 ] 2>/dev/null; then
        BAD_COUNT=$((BAD_COUNT + 1))
    else
        C_SCALED=$((C * 1000))
        T_INT=$(echo "$THRESHOLD" | awk '{printf "%d", $1 * 1000}')
        R_SCALED=$((R * T_INT / 1000))
        if [ "$C_SCALED" -gt "$R_SCALED" ] 2>/dev/null; then
            BAD_COUNT=$((BAD_COUNT + 1))
        fi
    fi
done < "$TMP_FILE"

rm -f "$TMP_FILE" 2>/dev/null

[ "$TURN_COUNT" -eq 0 ] && exit 0
[ "$BAD_COUNT" -lt "$STREAK" ] 2>/dev/null && exit 0

# --- Calculate ratio ---
if [ "$TOTAL_READ" -gt 0 ] 2>/dev/null; then
    RATIO=$(awk "BEGIN{printf \"%.1f\", ${TOTAL_CREATION}/${TOTAL_READ}}")
else
    RATIO="inf"
fi

# --- Save state ---
NOW=$(date +%s 2>/dev/null || echo 0)
cat > "$STATE_FILE" <<EOF
last_warn: ${NOW}
last_creation: ${TOTAL_CREATION}
last_read: ${TOTAL_READ}
last_ratio: ${RATIO}
bad_count: ${BAD_COUNT}
turns_analyzed: ${TURN_COUNT}
EOF

# --- Respond ---
if [ "$MODE" = "block" ]; then
    MSG=$(msg_get block_reason "Cache catcher: cache writes exceed reads. Ratio: ${RATIO}x")
    MSG="${MSG//\{creation\}/$TOTAL_CREATION}"
    MSG="${MSG//\{read\}/$TOTAL_READ}"
    MSG="${MSG//\{ratio\}/$RATIO}"
    MSG="${MSG//\{count\}/$BAD_COUNT}"
    _cc_deny "$MSG"
else
    MSG=$(msg_get warning "CACHE ANOMALY: cache writes exceed reads. Ratio: ${RATIO}x")
    MSG="${MSG//\{creation\}/$TOTAL_CREATION}"
    MSG="${MSG//\{read\}/$TOTAL_READ}"
    MSG="${MSG//\{ratio\}/$RATIO}"
    MSG="${MSG//\{count\}/$BAD_COUNT}"
    _cc_warn "$MSG"
fi

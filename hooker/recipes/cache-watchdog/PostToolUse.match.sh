#!/bin/bash
# Cache Watchdog — detect broken prompt caching from transcript usage data
source "${HOOKER_HELPERS}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE=".claude/hooker/cache-watchdog.config.yml"
[ -f "$CONFIG_FILE" ] || CONFIG_FILE="${SCRIPT_DIR}/config.yml"

STATE_DIR="${HOOKER_PROJECT_DIR:-.claude/hooker}"
STATE_FILE="${STATE_DIR}/cache-watchdog.state"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$CONFIG_FILE" 2>/dev/null | head -1 || echo "$2"
}

MSGS_FILE=".claude/hooker/cache-watchdog.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

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

# Need transcript
[ -z "${HOOKER_TRANSCRIPT:-}" ] && exit 1
[ -f "${HOOKER_TRANSCRIPT}" ] || exit 1

# Read stdin (PostToolUse JSON) but we mainly need transcript
INPUT=$(cat)

# Cooldown check
mkdir -p "$STATE_DIR" 2>/dev/null
if [ -f "$STATE_FILE" ]; then
    LAST_WARN=$(sed -n 's/^last_warn:[[:space:]]*//p' "$STATE_FILE" 2>/dev/null | head -1)
    if [ -n "$LAST_WARN" ]; then
        NOW=$(date +%s 2>/dev/null || echo 0)
        ELAPSED=$((NOW - LAST_WARN))
        [ "$ELAPSED" -lt "$COOLDOWN" ] 2>/dev/null && exit 1
    fi
fi

# Extract usage data from recent assistant turns
# Each assistant line has "usage":{...} with cache fields
# We parse the last N assistant turns
USAGE_DATA=$(grep '"type":"assistant"' "${HOOKER_TRANSCRIPT}" | \
    grep '"usage"' | \
    sed 's/.*"usage":{/{"usage":{/' | \
    sed 's/},.*/}}/' | \
    tail -n "$LOOKBACK")

[ -z "$USAGE_DATA" ] && exit 1

# Count total turns for ignore_first_turn
TOTAL_TURNS=$(grep -c '"type":"assistant"' "${HOOKER_TRANSCRIPT}" 2>/dev/null || echo 0)
if [ "$IGNORE_FIRST" = "true" ] && [ "$TOTAL_TURNS" -le 1 ]; then
    exit 1
fi

# Parse each turn's cache metrics
BAD_STREAK=0
TOTAL_CREATION=0
TOTAL_READ=0
TURN_COUNT=0
SKIP_FIRST=0

if [ "$IGNORE_FIRST" = "true" ]; then
    # If we're looking at the very start, skip first turn
    FIRST_OFFSET=$((TOTAL_TURNS - LOOKBACK))
    [ "$FIRST_OFFSET" -le 0 ] && SKIP_FIRST=1
fi

echo "$USAGE_DATA" | while IFS= read -r LINE; do
    [ -z "$LINE" ] && continue

    CREATION=$(echo "$LINE" | sed -n 's/.*"cache_creation_input_tokens":\([0-9]*\).*/\1/p' | head -1)
    READ=$(echo "$LINE" | sed -n 's/.*"cache_read_input_tokens":\([0-9]*\).*/\1/p' | head -1)

    CREATION="${CREATION:-0}"
    READ="${READ:-0}"

    # Skip first turn if configured
    if [ "$SKIP_FIRST" -eq 1 ]; then
        SKIP_FIRST=0
        continue
    fi

    echo "${CREATION}:${READ}"
done > "${STATE_DIR}/cache-watchdog.tmp" 2>/dev/null

# Analyze collected data
BAD_COUNT=0
LAST_CREATION=0
LAST_READ=0
TOTAL_CREATION=0
TOTAL_READ=0
TURN_COUNT=0

while IFS=: read -r C R; do
    [ -z "$C" ] && continue
    TURN_COUNT=$((TURN_COUNT + 1))
    TOTAL_CREATION=$((TOTAL_CREATION + C))
    TOTAL_READ=$((TOTAL_READ + R))
    LAST_CREATION=$C
    LAST_READ=$R

    # Skip small writes
    [ "$C" -lt "$MIN_TOKENS" ] 2>/dev/null && continue

    # Check ratio: creation / read > threshold
    # Avoid division — use cross-multiplication: creation * 10 > read * threshold * 10
    if [ "$R" -eq 0 ] 2>/dev/null; then
        # No cache read at all — definitely bad
        BAD_COUNT=$((BAD_COUNT + 1))
    else
        # creation / read > threshold  <==>  creation * 1000 > read * threshold * 1000
        C_SCALED=$((C * 1000))
        # Parse threshold as integer (1.0 -> 1000, 0.5 -> 500)
        T_INT=$(echo "$THRESHOLD" | awk '{printf "%d", $1 * 1000}')
        R_SCALED=$((R * T_INT / 1000))
        if [ "$C_SCALED" -gt "$R_SCALED" ] 2>/dev/null; then
            BAD_COUNT=$((BAD_COUNT + 1))
        fi
    fi
done < "${STATE_DIR}/cache-watchdog.tmp"

rm -f "${STATE_DIR}/cache-watchdog.tmp" 2>/dev/null

[ "$TURN_COUNT" -eq 0 ] && exit 1
[ "$BAD_COUNT" -lt "$STREAK" ] 2>/dev/null && exit 1

# Calculate ratio for message
if [ "$TOTAL_READ" -gt 0 ] 2>/dev/null; then
    RATIO=$(awk "BEGIN{printf \"%.1f\", ${TOTAL_CREATION}/${TOTAL_READ}}")
else
    RATIO="inf"
fi

# Save state
NOW=$(date +%s 2>/dev/null || echo 0)
cat > "$STATE_FILE" <<EOF
last_warn: ${NOW}
last_creation: ${TOTAL_CREATION}
last_read: ${TOTAL_READ}
last_ratio: ${RATIO}
bad_count: ${BAD_COUNT}
turns_analyzed: ${TURN_COUNT}
EOF

if [ "$MODE" = "block" ]; then
    MSG=$(msg_get block_reason "Cache watchdog: cache writes exceed reads. Ratio: ${RATIO}x")
    MSG="${MSG//\{creation\}/$TOTAL_CREATION}"
    MSG="${MSG//\{read\}/$TOTAL_READ}"
    MSG="${MSG//\{ratio\}/$RATIO}"
    MSG="${MSG//\{count\}/$BAD_COUNT}"
    deny "$MSG"
    exit 0
else
    MSG=$(msg_get warning "CACHE ANOMALY: cache writes exceed reads. Ratio: ${RATIO}x")
    MSG="${MSG//\{creation\}/$TOTAL_CREATION}"
    MSG="${MSG//\{read\}/$TOTAL_READ}"
    MSG="${MSG//\{ratio\}/$RATIO}"
    MSG="${MSG//\{count\}/$BAD_COUNT}"
    warn "$MSG"
    exit 0
fi

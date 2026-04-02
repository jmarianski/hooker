#!/bin/bash
# cache-catcher — CLI tool for cache usage analysis
# Usage: cache-catcher.sh <command> [options]
#
# Commands:
#   status          Show current session cache health
#   history         Show cache metrics per turn
#   sessions        List sessions with cache stats
#   watch           Continuously monitor (like tail -f)
#   config          Show current configuration
#
# Options:
#   -s, --session ID    Analyze specific session (default: latest)
#   -n, --last N        Show last N turns (default: all)
#   -j, --json          Output as JSON
#   -t, --threshold N   Override threshold for status check
#   -p, --project DIR   Project directory (default: CWD)

set -e

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
SEP="─────────────────────────────────────────────────────────────────────────"

# --- Defaults ---
CMD=""
SESSION=""
LAST_N=0
JSON_OUT=0
THRESHOLD="1.0"
PROJECT_DIR="$(pwd)"

# --- Parse args ---
while [ $# -gt 0 ]; do
    case "$1" in
        status|history|sessions|watch|config) CMD="$1" ;;
        -s|--session) SESSION="$2"; shift ;;
        -n|--last) LAST_N="$2"; shift ;;
        -j|--json) JSON_OUT=1 ;;
        -t|--threshold) THRESHOLD="$2"; shift ;;
        -p|--project) PROJECT_DIR="$2"; shift ;;
        -h|--help)
            sed -n '2,/^$/s/^# \{0,1\}//p' "$0"
            exit 0
            ;;
        *) echo "Unknown: $1. Use -h for help." >&2; exit 1 ;;
    esac
    shift
done

[ -z "$CMD" ] && CMD="status"

# --- Find project transcript dir ---
find_project_dir() {
    local SLUG
    SLUG=$(echo "$PROJECT_DIR" | sed 's|^/||; s|/|-|g')
    local PDIR="${HOME}/.claude/projects/-${SLUG}"
    [ -d "$PDIR" ] && echo "$PDIR" && return
    PDIR="${HOME}/.claude/projects/${SLUG}"
    [ -d "$PDIR" ] && echo "$PDIR" && return
    echo ""
}

PROJ_DIR=$(find_project_dir)
if [ -z "$PROJ_DIR" ]; then
    echo -e "${RED}No Claude project found for ${PROJECT_DIR}${NC}" >&2
    echo "Check if you've run Claude Code in this directory." >&2
    exit 1
fi

# --- Find transcript ---
find_transcript() {
    if [ -n "$SESSION" ]; then
        local F
        F=$(find "$PROJ_DIR" -maxdepth 2 -name "${SESSION}*.jsonl" -type f 2>/dev/null | head -1)
        [ -n "$F" ] && echo "$F" && return
        F=$(find "$PROJ_DIR" -name "${SESSION}*.jsonl" -type f 2>/dev/null | head -1)
        echo "$F"
    else
        find "$PROJ_DIR" -maxdepth 1 -name "*.jsonl" -type f 2>/dev/null | \
            while read -r f; do echo "$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) $f"; done | \
            sort -rn | head -1 | awk '{print $2}'
    fi
}

# --- Extract cache metrics from transcript ---
# Output: turn_number:creation:read:input:output:timestamp
extract_metrics() {
    local TRANSCRIPT="$1"
    local TURN=0

    grep '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null | while IFS= read -r LINE; do
        TURN=$((TURN + 1))

        CREATION=$(echo "$LINE" | sed -n 's/.*"cache_creation_input_tokens":\([0-9]*\).*/\1/p' | head -1)
        READ=$(echo "$LINE" | sed -n 's/.*"cache_read_input_tokens":\([0-9]*\).*/\1/p' | head -1)
        INPUT=$(echo "$LINE" | sed -n 's/.*"input_tokens":\([0-9]*\).*/\1/p' | head -1)
        OUTPUT=$(echo "$LINE" | sed -n 's/.*"output_tokens":\([0-9]*\).*/\1/p' | head -1)
        TS=$(echo "$LINE" | sed -n 's/.*"timestamp"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

        echo "${TURN}|${CREATION:-0}|${READ:-0}|${INPUT:-0}|${OUTPUT:-0}|${TS:-?}"
    done
}

# --- Resume detection ---
# A turn is a resume boundary if:
#   - read=0 AND creation=0 (empty reconnect turn), OR
#   - previous turn had normal cache, this turn has creation >> read with a big jump
# Returns "resume" or "" for each turn
detect_resume() {
    local PREV_C=0 PREV_R=0 PREV_TS=""
    while IFS='|' read -r T C R I O TS; do
        IS_RESUME=""

        # Empty turn (read=0, creation=0) = resume boundary
        if [ "$C" -eq 0 ] 2>/dev/null && [ "$R" -eq 0 ] 2>/dev/null; then
            IS_RESUME="boundary"
        fi

        # First turn after resume: huge creation spike with low/no read
        # Heuristic: creation > 50k and (read=0 or creation/read > 5)
        if [ "$PREV_C" -eq 0 ] 2>/dev/null && [ "$PREV_R" -eq 0 ] 2>/dev/null && [ "$C" -gt 50000 ] 2>/dev/null; then
            IS_RESUME="rebuild"
        fi

        # Timestamp gap > 120 seconds = likely resume
        if [ -n "$PREV_TS" ] && [ -n "$TS" ] && [ "$TS" != "?" ] && [ "$PREV_TS" != "?" ]; then
            # Extract epoch-like comparison from HH:MM:SS
            CUR_S=$(echo "$TS" | sed 's/.*T//' | awk -F: '{print ($1*3600)+($2*60)+$3}' 2>/dev/null)
            PREV_S=$(echo "$PREV_TS" | sed 's/.*T//' | awk -F: '{print ($1*3600)+($2*60)+$3}' 2>/dev/null)
            if [ -n "$CUR_S" ] && [ -n "$PREV_S" ]; then
                GAP=$((CUR_S - PREV_S))
                # Handle midnight wraparound
                [ "$GAP" -lt 0 ] && GAP=$((GAP + 86400))
                if [ "$GAP" -gt 120 ] 2>/dev/null && [ -z "$IS_RESUME" ]; then
                    IS_RESUME="gap"
                fi
            fi
        fi

        echo "${T}|${C}|${R}|${I}|${O}|${TS}|${IS_RESUME}"
        PREV_C=$C
        PREV_R=$R
        PREV_TS=$TS
    done
}

# --- Verdict for a single turn ---
verdict() {
    local C="$1" R="$2" RESUME="$3"
    # Resume turns get special verdict
    if [ "$RESUME" = "boundary" ]; then
        echo "resume"
        return
    fi
    if [ "$RESUME" = "rebuild" ] || [ "$RESUME" = "gap" ]; then
        echo "resume"
        return
    fi
    if [ "$C" -lt 5000 ] 2>/dev/null; then
        echo "ok"
    elif [ "$R" -eq 0 ] 2>/dev/null; then
        echo "miss"
    else
        local C_S=$((C * 1000))
        local T_INT=$(echo "$THRESHOLD" | awk '{printf "%d", $1 * 1000}')
        local R_S=$((R * T_INT / 1000))
        if [ "$C_S" -gt "$R_S" ] 2>/dev/null; then
            echo "bad"
        else
            echo "good"
        fi
    fi
}

verdict_color() {
    case "$1" in
        good)   echo "${GREEN}" ;;
        ok)     echo "${CYAN}" ;;
        bad)    echo "${RED}" ;;
        miss)   echo "${RED}" ;;
        resume) echo "${YELLOW}" ;;
        *)      echo "${NC}" ;;
    esac
}

verdict_icon() {
    case "$1" in
        good)   echo "●" ;;
        ok)     echo "○" ;;
        bad)    echo "✗" ;;
        miss)   echo "✗" ;;
        resume) echo "↻" ;;
    esac
}

fmt_tokens() {
    local N="$1"
    if [ "$N" -ge 1000000 ] 2>/dev/null; then
        awk "BEGIN{printf \"%.1fM\", ${N}/1000000}"
    elif [ "$N" -ge 1000 ] 2>/dev/null; then
        awk "BEGIN{printf \"%.1fk\", ${N}/1000}"
    else
        echo "$N"
    fi
}

# --- Commands ---

cmd_status() {
    local TRANSCRIPT
    TRANSCRIPT=$(find_transcript)
    [ -z "$TRANSCRIPT" ] && echo -e "${RED}No transcript found.${NC}" && exit 1

    local SESSION_ID
    SESSION_ID=$(basename "$TRANSCRIPT" .jsonl)
    local TOTAL_TURNS
    TOTAL_TURNS=$(grep -c '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null || echo 0)

    echo -e "${BOLD}Cache Catcher Status${NC}"
    echo -e "${DIM}Session: ${SESSION_ID}${NC}"
    echo -e "${DIM}Turns:   ${TOTAL_TURNS}${NC}"
    echo ""

    if [ "$TOTAL_TURNS" -eq 0 ]; then
        echo -e "${YELLOW}No assistant turns found.${NC}"
        return
    fi

    local METRICS
    METRICS=$(extract_metrics "$TRANSCRIPT")

    # Apply -n for status too
    if [ "$LAST_N" -gt 0 ] 2>/dev/null; then
        METRICS=$(echo "$METRICS" | tail -n "$LAST_N")
    fi

    # Add resume detection
    METRICS_WITH_RESUME=$(echo "$METRICS" | detect_resume)

    echo "$METRICS_WITH_RESUME" | while IFS='|' read -r T C R I O TS RESUME; do
        [ -z "$T" ] && continue
        V=$(verdict "$C" "$R" "$RESUME")
        TOTAL_C=$((${TOTAL_C:-0} + C))
        TOTAL_R=$((${TOTAL_R:-0} + R))
        RESUMES=$((${RESUMES:-0}))
        case "$V" in
            bad|miss) BAD=$((${BAD:-0} + 1)) ;;
            resume) RESUMES=$((RESUMES + 1)) ;;
        esac
        echo "${TOTAL_C}:${TOTAL_R}:${BAD:-0}:${C}:${R}:${RESUMES}" > /tmp/cache-catcher-status.tmp
    done

    if [ -f /tmp/cache-catcher-status.tmp ]; then
        IFS=: read -r TOTAL_C TOTAL_R BAD LAST_C LAST_R RESUMES < /tmp/cache-catcher-status.tmp
        rm -f /tmp/cache-catcher-status.tmp

        ANALYZED=$TOTAL_TURNS
        [ "$LAST_N" -gt 0 ] 2>/dev/null && ANALYZED=$LAST_N

        if [ "$TOTAL_R" -gt 0 ] 2>/dev/null; then
            RATIO=$(awk "BEGIN{printf \"%.2f\", ${TOTAL_C}/${TOTAL_R}}")
        else
            RATIO="inf"
        fi

        if [ "${BAD:-0}" -eq 0 ] 2>/dev/null; then
            echo -e "${GREEN}${BOLD}  HEALTHY${NC}  Cache is working properly"
        elif [ "${BAD:-0}" -le 1 ] 2>/dev/null; then
            echo -e "${YELLOW}${BOLD}  WARNING${NC}  Occasional cache misses detected"
        else
            echo -e "${RED}${BOLD}  BROKEN${NC}   Cache is consistently breaking"
        fi

        echo ""
        echo -e "  Total cache_read:     ${BOLD}$(fmt_tokens "$TOTAL_R")${NC}"
        echo -e "  Total cache_creation: ${BOLD}$(fmt_tokens "$TOTAL_C")${NC}"
        echo -e "  Creation/Read ratio:  ${BOLD}${RATIO}${NC}"
        echo -e "  Bad turns:            ${BOLD}${BAD:-0}${NC} / ${ANALYZED}"
        [ "${RESUMES:-0}" -gt 0 ] && echo -e "  Resumes detected:     ${BOLD}${RESUMES}${NC}"
        echo ""
        echo -e "  Last turn: read=$(fmt_tokens "$LAST_R") creation=$(fmt_tokens "$LAST_C")"
    fi
}

cmd_history() {
    local TRANSCRIPT
    TRANSCRIPT=$(find_transcript)
    [ -z "$TRANSCRIPT" ] && echo -e "${RED}No transcript found.${NC}" && exit 1

    local SESSION_ID
    SESSION_ID=$(basename "$TRANSCRIPT" .jsonl)

    echo -e "${BOLD}Cache History${NC} ${DIM}(session: ${SESSION_ID})${NC}"
    echo ""
    printf "${DIM}%-5s %-10s %-10s %-8s %-8s %s${NC}\n" "Turn" "Read" "Creation" "Ratio" "Status" "Time"
    echo -e "${DIM}${SEP}${NC}"

    local METRICS
    METRICS=$(extract_metrics "$TRANSCRIPT")

    if [ "$LAST_N" -gt 0 ] 2>/dev/null; then
        METRICS=$(echo "$METRICS" | tail -n "$LAST_N")
    fi

    # Add resume detection
    METRICS_WITH_RESUME=$(echo "$METRICS" | detect_resume)

    echo "$METRICS_WITH_RESUME" | while IFS='|' read -r T C R I O TS RESUME; do
        [ -z "$T" ] && continue
        V=$(verdict "$C" "$R" "$RESUME")
        VC=$(verdict_color "$V")
        VI=$(verdict_icon "$V")

        if [ "$R" -gt 0 ] 2>/dev/null; then
            RATIO=$(awk "BEGIN{printf \"%.2f\", ${C}/${R}}")
        elif [ "$C" -gt 0 ] 2>/dev/null; then
            RATIO="inf"
        else
            RATIO="0.00"
        fi

        TIME=$(echo "$TS" | sed 's/.*T\([0-9:]*\).*/\1/' | cut -c1-8)

        printf "%-5s %-10s %-10s %-8s ${VC}%-8s${NC} %s\n" \
            "$T" "$(fmt_tokens "$R")" "$(fmt_tokens "$C")" "$RATIO" "${VI} ${V}" "$TIME"
    done
}

cmd_sessions() {
    echo -e "${BOLD}Sessions with Cache Stats${NC}"
    echo ""
    printf "${DIM}%-38s %-6s %-10s %-10s %-8s %s${NC}\n" "Session" "Turns" "Read" "Creation" "Ratio" "Status"
    echo -e "${DIM}${SEP}${SEP}${NC}"

    find "$PROJ_DIR" -maxdepth 1 -name "*.jsonl" -type f 2>/dev/null | sort | while read -r F; do
        SID=$(basename "$F" .jsonl)
        TURNS=$(grep -c '"type":"assistant"' "$F" 2>/dev/null || echo 0)
        [ "$TURNS" -eq 0 ] && continue

        grep '"type":"assistant"' "$F" 2>/dev/null | while IFS= read -r LINE; do
            C=$(echo "$LINE" | sed -n 's/.*"cache_creation_input_tokens":\([0-9]*\).*/\1/p' | head -1)
            R=$(echo "$LINE" | sed -n 's/.*"cache_read_input_tokens":\([0-9]*\).*/\1/p' | head -1)
            C="${C:-0}"
            R="${R:-0}"
            TOTAL_C=$((${TOTAL_C:-0} + C))
            TOTAL_R=$((${TOTAL_R:-0} + R))
            V=$(verdict "$C" "$R" "")
            case "$V" in bad|miss) BAD=$((${BAD:-0} + 1)) ;; esac
            echo "${TOTAL_C}:${TOTAL_R}:${BAD:-0}" > /tmp/cc-sess.tmp
        done

        if [ -f /tmp/cc-sess.tmp ]; then
            IFS=: read -r TOTAL_C TOTAL_R BAD < /tmp/cc-sess.tmp
            rm -f /tmp/cc-sess.tmp

            if [ "$TOTAL_R" -gt 0 ] 2>/dev/null; then
                RATIO=$(awk "BEGIN{printf \"%.2f\", ${TOTAL_C}/${TOTAL_R}}")
            else
                RATIO="inf"
            fi

            if [ "${BAD:-0}" -eq 0 ] 2>/dev/null; then
                STATUS="${GREEN}healthy${NC}"
            elif [ "${BAD:-0}" -le 1 ]; then
                STATUS="${YELLOW}warning${NC}"
            else
                STATUS="${RED}broken${NC}"
            fi

            printf "%-38s %-6s %-10s %-10s %-8s " "$SID" "$TURNS" "$(fmt_tokens "$TOTAL_R")" "$(fmt_tokens "$TOTAL_C")" "$RATIO"
            echo -e "$STATUS"
        fi
    done
}

cmd_watch() {
    local TRANSCRIPT
    TRANSCRIPT=$(find_transcript)
    [ -z "$TRANSCRIPT" ] && echo -e "${RED}No transcript found.${NC}" && exit 1

    echo -e "${BOLD}Cache Catcher — Live Monitor${NC} ${DIM}(Ctrl+C to stop)${NC}"
    echo ""

    local LAST_LINES=0
    while true; do
        CURRENT_LINES=$(grep -c '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null || echo 0)
        if [ "$CURRENT_LINES" -gt "$LAST_LINES" ] 2>/dev/null; then
            LAST_LINE=$(grep '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null | tail -1)
            C=$(echo "$LAST_LINE" | sed -n 's/.*"cache_creation_input_tokens":\([0-9]*\).*/\1/p' | head -1)
            R=$(echo "$LAST_LINE" | sed -n 's/.*"cache_read_input_tokens":\([0-9]*\).*/\1/p' | head -1)
            C="${C:-0}"
            R="${R:-0}"
            V=$(verdict "$C" "$R" "")
            VC=$(verdict_color "$V")
            NOW=$(date '+%H:%M:%S')

            if [ "$R" -gt 0 ] 2>/dev/null; then
                RATIO=$(awk "BEGIN{printf \"%.2f\", ${C}/${R}}")
            else
                RATIO="inf"
            fi

            printf "${DIM}[%s]${NC} Turn %s: read=%-8s creation=%-8s ratio=%-6s ${VC}%s${NC}\n" \
                "$NOW" "$CURRENT_LINES" "$(fmt_tokens "$R")" "$(fmt_tokens "$C")" "$RATIO" "$(verdict_icon "$V") $V"

            LAST_LINES=$CURRENT_LINES
        fi
        sleep 2
    done
}

cmd_config() {
    echo -e "${BOLD}Cache Catcher Configuration${NC}"
    echo ""

    local CFG=".claude/cache-catcher.config.yml"
    if [ -f "$CFG" ]; then
        echo -e "${DIM}Source: ${CFG} (project override)${NC}"
    else
        local RECIPE_DIR
        RECIPE_DIR=$(dirname "$0")
        CFG="${RECIPE_DIR}/../config.yml"
        echo -e "${DIM}Source: ${CFG} (default)${NC}"
    fi
    echo ""

    if [ -f "$CFG" ]; then
        while IFS= read -r LINE; do
            case "$LINE" in
                \#*) echo -e "${DIM}${LINE}${NC}" ;;
                "") echo "" ;;
                *)
                    KEY=$(echo "$LINE" | cut -d: -f1)
                    VAL=$(echo "$LINE" | cut -d: -f2- | sed 's/^[[:space:]]*//')
                    echo -e "  ${BOLD}${KEY}${NC}: ${CYAN}${VAL}${NC}"
                    ;;
            esac
        done < "$CFG"
    fi
}

# --- JSON output wrapper ---
if [ "$JSON_OUT" -eq 1 ]; then
    case "$CMD" in
        status)
            TRANSCRIPT=$(find_transcript)
            [ -z "$TRANSCRIPT" ] && echo '{"error":"no transcript"}' && exit 1
            METRICS=$(extract_metrics "$TRANSCRIPT")
            [ "$LAST_N" -gt 0 ] 2>/dev/null && METRICS=$(echo "$METRICS" | tail -n "$LAST_N")
            METRICS_R=$(echo "$METRICS" | detect_resume)
            echo "$METRICS_R" | while IFS='|' read -r T C R I O TS RESUME; do
                V=$(verdict "$C" "$R" "$RESUME")
                TOTAL_C=$((${TOTAL_C:-0} + C))
                TOTAL_R=$((${TOTAL_R:-0} + R))
                TURNS=$((${TURNS:-0} + 1))
                RESUMES=$((${RESUMES:-0}))
                case "$V" in
                    bad|miss) BAD=$((${BAD:-0} + 1)) ;;
                    resume) RESUMES=$((RESUMES + 1)) ;;
                esac
                echo "${TOTAL_C}:${TOTAL_R}:${BAD:-0}:${TURNS}:${RESUMES}" > /tmp/cc-json.tmp
            done
            if [ -f /tmp/cc-json.tmp ]; then
                IFS=: read -r TC TR B TN RS < /tmp/cc-json.tmp
                rm -f /tmp/cc-json.tmp
                if [ "$TR" -gt 0 ] 2>/dev/null; then
                    RATIO=$(awk "BEGIN{printf \"%.4f\", ${TC}/${TR}}")
                else
                    RATIO="null"
                fi
                printf '{"session":"%s","turns":%s,"total_read":%s,"total_creation":%s,"ratio":%s,"bad_turns":%s,"resumes":%s}\n' \
                    "$(basename "$TRANSCRIPT" .jsonl)" "$TN" "$TR" "$TC" "$RATIO" "$B" "$RS"
            fi
            ;;
        history)
            TRANSCRIPT=$(find_transcript)
            [ -z "$TRANSCRIPT" ] && echo '{"error":"no transcript"}' && exit 1
            METRICS=$(extract_metrics "$TRANSCRIPT")
            [ "$LAST_N" -gt 0 ] 2>/dev/null && METRICS=$(echo "$METRICS" | tail -n "$LAST_N")
            METRICS_R=$(echo "$METRICS" | detect_resume)
            echo '['
            FIRST=1
            echo "$METRICS_R" | while IFS='|' read -r T C R I O TS RESUME; do
                [ -z "$T" ] && continue
                V=$(verdict "$C" "$R" "$RESUME")
                if [ "$R" -gt 0 ] 2>/dev/null; then
                    RATIO=$(awk "BEGIN{printf \"%.4f\", ${C}/${R}}")
                else
                    RATIO="null"
                fi
                [ "$FIRST" -eq 1 ] && FIRST=0 || printf ','
                printf '{"turn":%s,"cache_read":%s,"cache_creation":%s,"input":%s,"output":%s,"ratio":%s,"verdict":"%s","resume":"%s","timestamp":"%s"}' \
                    "$T" "$R" "$C" "$I" "$O" "$RATIO" "$V" "$RESUME" "$TS"
            done
            echo ']'
            ;;
        *) echo '{"error":"JSON output only for status and history"}' ;;
    esac
    exit 0
fi

# --- Dispatch ---
case "$CMD" in
    status)   cmd_status ;;
    history)  cmd_history ;;
    sessions) cmd_sessions ;;
    watch)    cmd_watch ;;
    config)   cmd_config ;;
    *)        echo "Unknown command: $CMD" >&2; exit 1 ;;
esac

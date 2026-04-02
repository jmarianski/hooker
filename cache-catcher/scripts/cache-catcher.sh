#!/bin/bash
# cache-catcher — CLI tool for cache usage analysis
# Usage: cache-catcher.sh <command> [options]
#
# Run with no command (or "help") to list commands.
#
# Commands:
#   help, -h, --help   List commands and options (default when no command)
#   status             Show current session cache health
#   history            Show cache metrics per turn
#   sessions           List sessions with cache stats
#   watch              Continuously monitor (like tail -f)
#   config [show]      Show effective hook config (default)
#   config init [-f]   Create .claude/cache-catcher.config.yml from plugin template
#   config get KEY     Print effective value for KEY (project override wins)
#   config set K V...  Set KEY in project file (creates file/dir if needed)
#   alias [print|set|clear]  Claude Code prompt prefixes (see help)
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
CONFIG_SUBCMD="show"
CONFIG_KEY=""
CONFIG_VAL=""
CONFIG_INIT_FORCE=0
ALIAS_SUBCMD="show"
ALIAS_SET_VAL=""
SESSION=""
LAST_N=0
JSON_OUT=0
THRESHOLD="1.0"
PROJECT_DIR="$(pwd)"

# --- Parse args ---
while [ $# -gt 0 ]; do
    case "$1" in
        status|history|sessions|watch) CMD="$1" ;;
        config)
            CMD="config"
            shift
            CONFIG_SUBCMD=show
            CONFIG_INIT_FORCE=0
            if [ -n "${1:-}" ]; then
                case "$1" in
                    init)
                        CONFIG_SUBCMD=init
                        shift
                        if [ "${1:-}" = "-f" ] || [ "${1:-}" = "--force" ]; then
                            CONFIG_INIT_FORCE=1
                            shift
                        fi
                        ;;
                    get)
                        CONFIG_SUBCMD=get
                        shift
                        CONFIG_KEY="${1:-}"
                        [ -z "$CONFIG_KEY" ] && echo "Usage: cache-catcher config get <key>" >&2 && exit 1
                        shift
                        ;;
                    set)
                        CONFIG_SUBCMD=set
                        shift
                        CONFIG_KEY="${1:-}"
                        [ -z "$CONFIG_KEY" ] && echo "Usage: cache-catcher config set <key> <value>" >&2 && exit 1
                        shift
                        CONFIG_VAL="$*"
                        [ -z "$CONFIG_VAL" ] && echo "Usage: cache-catcher config set <key> <value>" >&2 && exit 1
                        set --
                        ;;
                    show)
                        CONFIG_SUBCMD=show
                        shift
                        ;;
                    *)
                        echo "Unknown config subcommand: $1 (use: show, init, get, set)" >&2
                        exit 1
                        ;;
                esac
            fi
            continue
            ;;
        help|-h|--help) CMD="help" ;;
        alias)
            CMD="alias"
            shift
            ALIAS_SUBCMD="show"
            case "${1:-}" in
                print)
                    ALIAS_SUBCMD="print"
                    shift
                    ;;
                set)
                    ALIAS_SUBCMD="set"
                    shift
                    ALIAS_SET_VAL="$*"
                    [ -z "$ALIAS_SET_VAL" ] && echo "Usage: cache-catcher alias set <prefix>[,prefix...]" >&2 && exit 1
                    set --
                    ;;
                clear)
                    ALIAS_SUBCMD="clear"
                    shift
                    ;;
            esac
            continue
            ;;
        -s|--session) SESSION="$2"; shift ;;
        -n|--last) LAST_N="$2"; shift ;;
        -j|--json) JSON_OUT=1 ;;
        -t|--threshold) THRESHOLD="$2"; shift ;;
        -p|--project) PROJECT_DIR="$2"; shift ;;
        *) echo "Unknown: $1. Use cache-catcher help." >&2; exit 1 ;;
    esac
    shift
done

# --- Help / alias (no Claude project required) ---
cmd_help() {
    echo -e "${BOLD}cache-catcher${NC} — cache usage analysis for Claude Code transcripts"
    echo ""
    echo -e "${BOLD}Usage:${NC} cache-catcher <command> [options]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  help              Show this list (also: no command, -h, --help)"
    echo "  status            Current session cache health summary"
    echo "  history           Per-turn cache read / creation metrics"
    echo "  sessions          All sessions (status = last 10 turns; -n N to change)"
    echo "  watch             Live monitor in a real terminal (not from Claude Code prompt)"
    echo "  config [show]     Show effective hook config (project vs plugin default)"
    echo "  config init [-f]  Create .claude/cache-catcher.config.yml from template"
    echo "  config get KEY    Print one setting (override wins)"
    echo "  config set K V    Set one field in project config"
    echo "  alias [print]     All UserPromptSubmit prefixes (for Claude Code), one CSV line"
    echo "  alias set A[,B]   Save extra prefixes in .claude/cache-catcher.config.yml"
    echo "  alias clear       Remove extra prefixes (only \"cache-catcher\" remains)"
    echo ""
    echo -e "${BOLD}Options:${NC} (for status, history, sessions, watch)"
    echo "  -s, --session ID   Session id prefix (default: latest transcript)"
    echo "  -n, --last N       Last N turns (status/history); sessions status window"
    echo "  -j, --json         JSON (status, history only)"
    echo "  -t, --threshold N  Ratio threshold for verdicts (default: 1.0)"
    echo "  -p, --project DIR  Repo root to resolve ~/.claude/projects/ (default: cwd)"
    echo ""
    echo -e "${DIM}Hook config: project file .claude/cache-catcher.config.yml overrides the plugin default.${NC}"
    echo -e "${DIM}Extra prompt prefixes: ${BOLD}cache-catcher alias${NC}${DIM} (config key ${BOLD}prompt_aliases${NC}${DIM}).${NC}"
}

cc_default_cfg() {
    echo "$(cd "$(dirname "$0")" && pwd)/../config.yml"
}

cc_project_cfg() {
    echo "${PROJECT_DIR}/.claude/cache-catcher.config.yml"
}

cc_config_valid_key() {
    case "$1" in
        mode|lookback|threshold|min_tokens|streak|cooldown|ignore_first_turn|prompt_aliases) return 0 ;;
        *)
            echo "Unknown key: $1" >&2
            echo "Allowed: mode lookback threshold min_tokens streak cooldown ignore_first_turn prompt_aliases" >&2
            return 1
            ;;
    esac
}

# Read scalar value for key from a cache-catcher style yml (key: value, no quotes required)
cc_yml_get() {
    local key="$1" file="$2"
    [ -f "$file" ] || return 0
    sed -n "s/^${key}:[[:space:]]*//p" "$file" 2>/dev/null | head -1 | sed 's/[[:space:]]*#.*$//;s/[[:space:]]*$//' | sed 's/^"\(.*\)"$/\1/'
}

cc_yml_update_or_append() {
    local k="$1" v="$2" f="$3"
    local t found=0 line pref dir
    dir=$(dirname "$f")
    mkdir -p "$dir"
    t=$(mktemp 2>/dev/null || echo "/tmp/cc-yml-$$.tmp")
    if [ -f "$f" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                \#*|'') echo "$line" >> "$t" ;;
                *)
                    pref=${line%%:*}
                    pref=$(echo "$pref" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    if [ "$pref" = "$k" ]; then
                        echo "${k}: ${v}" >> "$t"
                        found=1
                    else
                        echo "$line" >> "$t"
                    fi
                    ;;
            esac
        done < "$f"
    fi
    if [ "$found" -eq 0 ]; then
        [ -s "$t" ] && echo "" >> "$t"
        echo "${k}: ${v}" >> "$t"
    fi
    mv "$t" "$f"
}

cmd_config_show() {
    echo -e "${BOLD}Cache Catcher Configuration${NC}"
    echo ""

    local PCFG
    PCFG=$(cc_project_cfg)
    local DEF
    DEF=$(cc_default_cfg)

    if [ -f "$PCFG" ]; then
        echo -e "${DIM}Source: ${PCFG} (project override)${NC}"
    else
        echo -e "${DIM}Source: ${DEF} (default — no project file)${NC}"
    fi
    echo -e "${DIM}Project root: ${PROJECT_DIR}${NC}"
    echo ""

    local CFG="$DEF"
    [ -f "$PCFG" ] && CFG="$PCFG"

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
    else
        echo -e "${YELLOW}No config file found at ${DEF}${NC}" >&2
    fi
}

cmd_config_init() {
    local PCFG DEF
    PCFG=$(cc_project_cfg)
    DEF=$(cc_default_cfg)
    if [ ! -f "$DEF" ]; then
        echo -e "${RED}Plugin template missing: ${DEF}${NC}" >&2
        exit 1
    fi
    if [ -f "$PCFG" ] && [ "$CONFIG_INIT_FORCE" -eq 0 ] 2>/dev/null; then
        echo -e "${YELLOW}Already exists: ${PCFG}${NC}" >&2
        echo "Use: cache-catcher config init --force" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$PCFG")"
    cp "$DEF" "$PCFG"
    echo -e "${GREEN}Wrote ${PCFG}${NC}"
}

cmd_config_get() {
    cc_config_valid_key "$1" || exit 1
    local PCFG DEF d p val
    DEF=$(cc_default_cfg)
    PCFG=$(cc_project_cfg)
    d=$(cc_yml_get "$1" "$DEF")
    p=""
    [ -f "$PCFG" ] && p=$(cc_yml_get "$1" "$PCFG")
    val="${p:-$d}"
    if [ -z "$val" ] && [ "$1" != "prompt_aliases" ]; then
        echo "(empty)" >&2
        exit 1
    fi
    printf '%s\n' "$val"
}

cmd_config_set() {
    cc_config_valid_key "$1" || exit 1
    local PCFG
    PCFG=$(cc_project_cfg)
    cc_yml_update_or_append "$1" "$2" "$PCFG"
    echo -e "${GREEN}Updated ${1} in ${PCFG}${NC}"
}

cmd_config_dispatch() {
    case "$CONFIG_SUBCMD" in
        show) cmd_config_show ;;
        init) cmd_config_init ;;
        get) cmd_config_get "$CONFIG_KEY" ;;
        set) cmd_config_set "$CONFIG_KEY" "$CONFIG_VAL" ;;
        *) echo "Internal error: bad config subcommand" >&2; exit 1 ;;
    esac
}

# Comma-separated extra prefixes (no spaces); drop invalid tokens; skip built-in name
cc_prompt_aliases_validate_and_format() {
    local raw="$1" out="" a
    OLD_IFS=$IFS
    IFS=','
    for a in $raw; do
        a=$(echo "$a" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$a" ] && continue
        case "$a" in
            ''|*[!a-zA-Z0-9_.-]*)
                echo "Invalid prefix '$a' (allowed: ASCII letters, digits, ._-)" >&2
                return 1
                ;;
        esac
        if [ "$a" = "cache-catcher" ]; then
            echo "Skipping 'cache-catcher' (always available)." >&2
            continue
        fi
        [ -n "$out" ] && out="${out},"
        out="${out}${a}"
    done
    IFS=$OLD_IFS
    printf '%s' "$out"
}

cc_prompt_aliases_format_csv() {
    local raw="$1" out="" a
    OLD_IFS=$IFS
    IFS=','
    for a in $raw; do
        a=$(echo "$a" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$a" ] && continue
        [ -n "$out" ] && out="${out},"
        out="${out}${a}"
    done
    IFS=$OLD_IFS
    printf '%s' "$out"
}

cc_effective_prompt_aliases() {
    local DEF PCFG
    DEF=$(cc_default_cfg)
    PCFG=$(cc_project_cfg)
    if [ -f "$PCFG" ] && grep -q "^[[:space:]]*prompt_aliases[[:space:]]*:" "$PCFG" 2>/dev/null; then
        cc_yml_get prompt_aliases "$PCFG"
        return
    fi
    cc_yml_get prompt_aliases "$DEF"
}

cmd_alias() {
    local PCFG csv ea norm
    PCFG=$(cc_project_cfg)
    case "$ALIAS_SUBCMD" in
        print)
            ea=$(cc_effective_prompt_aliases)
            csv=$(cc_prompt_aliases_format_csv "$ea")
            if [ -n "$csv" ]; then
                printf 'cache-catcher,%s\n' "$csv"
            else
                printf 'cache-catcher\n'
            fi
            ;;
        set)
            norm=$(cc_prompt_aliases_validate_and_format "$ALIAS_SET_VAL") || exit 1
            mkdir -p "$(dirname "$PCFG")"
            cc_yml_update_or_append prompt_aliases "$norm" "$PCFG"
            echo -e "${GREEN}Wrote prompt_aliases to ${PCFG}${NC}"
            ea=$(cc_effective_prompt_aliases)
            csv=$(cc_prompt_aliases_format_csv "$ea")
            if [ -n "$csv" ]; then
                echo -e "${DIM}Effective prefixes:${NC} cache-catcher,${csv}"
            else
                echo -e "${DIM}Effective prefixes:${NC} cache-catcher"
            fi
            ;;
        clear)
            mkdir -p "$(dirname "$PCFG")"
            cc_yml_update_or_append prompt_aliases "" "$PCFG"
            echo -e "${GREEN}Cleared prompt_aliases in ${PCFG} (only cache-catcher works).${NC}"
            ;;
        show)
            echo -e "${BOLD}Claude Code command prefixes${NC} ${DIM}(UserPromptSubmit → CLI)${NC}"
            echo ""
            echo -e "  ${BOLD}cache-catcher${NC}  always recognized"
            ea=$(cc_effective_prompt_aliases)
            csv=$(cc_prompt_aliases_format_csv "$ea")
            if [ -n "$csv" ]; then
                echo -e "  ${BOLD}extras${NC}         ${CYAN}${csv}${NC} ${DIM}(from prompt_aliases in config)${NC}"
            else
                echo -e "  ${DIM}extras         (none — set e.g. ${BOLD}cache-catcher alias set cc${DIM})${NC}"
            fi
            echo ""
            echo -e "${DIM}Edit with:${NC} ${CYAN}cache-catcher alias set cc,dbg${NC} ${DIM}or${NC} ${CYAN}config set prompt_aliases \"cc\"${NC}"
            echo -e "${DIM}Machine-readable list:${NC} ${CYAN}cache-catcher alias print${NC}"
            echo -e "${DIM}Project file:${NC} ${PCFG}"
            ;;
        *)
            echo "Internal error: bad alias subcommand" >&2
            exit 1
            ;;
    esac
}

case "$CMD" in
    ""|help)
        cmd_help
        exit 0
        ;;
    alias)
        cmd_alias
        exit 0
        ;;
    config)
        cmd_config_dispatch
        exit 0
        ;;
esac

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

# grep -c exits 1 when count is 0; never use "|| echo 0" (yields "0\n0" and breaks test -eq).
count_assistant_turns() {
    local f="$1"
    local n
    n=$(grep -c '"type":"assistant"' "$f" 2>/dev/null) || true
    echo "${n:-0}"
}

# --- Resume detection ---
# Detects resume boundaries and classifies cache rebuilds:
#   - boundary: empty turn (read=0, creation=0) = reconnect
#   - rebuild_short: cache miss within 1h of last turn (cache should still be warm = bad)
#   - rebuild_long: cache miss after >1h gap (cache expired = expected, yellow)
#   - gap: timestamp gap >2min without empty boundary turn
detect_resume() {
    local PREV_C=0 PREV_R=0 PREV_TS=""
    local IN_BOUNDARY=0 BOUNDARY_GAP=0
    while IFS='|' read -r T C R I O TS; do
        IS_RESUME=""

        # Calculate gap from previous turn
        GAP=0
        if [ -n "$PREV_TS" ] && [ -n "$TS" ] && [ "$TS" != "?" ] && [ "$PREV_TS" != "?" ]; then
            CUR_S=$(echo "$TS" | sed 's/.*T//' | awk -F: '{print ($1*3600)+($2*60)+$3}' 2>/dev/null)
            PREV_S=$(echo "$PREV_TS" | sed 's/.*T//' | awk -F: '{print ($1*3600)+($2*60)+$3}' 2>/dev/null)
            if [ -n "$CUR_S" ] && [ -n "$PREV_S" ]; then
                GAP=$((CUR_S - PREV_S))
                [ "$GAP" -lt 0 ] && GAP=$((GAP + 86400))
            fi
        fi

        # Empty turn (read=0, creation=0) = resume boundary
        if [ "$C" -eq 0 ] 2>/dev/null && [ "$R" -eq 0 ] 2>/dev/null; then
            IS_RESUME="boundary"
            IN_BOUNDARY=1
            BOUNDARY_GAP=$GAP
        # First turn after boundary: classify by gap duration
        elif [ "$IN_BOUNDARY" -eq 1 ] 2>/dev/null && [ "$C" -gt 50000 ] 2>/dev/null; then
            TOTAL_GAP=$((BOUNDARY_GAP + GAP))
            if [ "$TOTAL_GAP" -gt 3600 ] 2>/dev/null; then
                IS_RESUME="rebuild_long"   # >1h gap, cache expired — expected
            else
                IS_RESUME="rebuild_short"  # <1h gap, cache should be warm — bad
            fi
            IN_BOUNDARY=0
            BOUNDARY_GAP=0
        else
            IN_BOUNDARY=0
            BOUNDARY_GAP=0
            # Standalone gap without boundary turn
            if [ "$GAP" -gt 120 ] 2>/dev/null && [ "$C" -gt 50000 ] 2>/dev/null; then
                if [ "$GAP" -gt 3600 ] 2>/dev/null; then
                    IS_RESUME="rebuild_long"
                else
                    IS_RESUME="rebuild_short"
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
    # Resume boundary (empty reconnect turn)
    if [ "$RESUME" = "boundary" ]; then
        echo "resume"
        return
    fi
    # Short resume (<1h): cache should still be warm — this is bad
    if [ "$RESUME" = "rebuild_short" ]; then
        echo "bad"
        return
    fi
    # Long resume (>1h): cache expired — expected, not an error
    if [ "$RESUME" = "rebuild_long" ]; then
        echo "expired"
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
        good)    echo "${GREEN}" ;;
        ok)      echo "${CYAN}" ;;
        bad)     echo "${RED}" ;;
        miss)    echo "${RED}" ;;
        resume)  echo "${YELLOW}" ;;
        expired) echo "${YELLOW}" ;;
        *)       echo "${NC}" ;;
    esac
}

verdict_icon() {
    case "$1" in
        good)    echo "●" ;;
        ok)      echo "○" ;;
        bad)     echo "✗" ;;
        miss)    echo "✗" ;;
        resume)  echo "↻" ;;
        expired) echo "◷" ;;
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
    TOTAL_TURNS=$(count_assistant_turns "$TRANSCRIPT")

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
    local WINDOW=10
    [ "$LAST_N" -gt 0 ] 2>/dev/null && WINDOW=$LAST_N

    echo -e "${BOLD}Sessions with Cache Stats${NC}"
    echo -e "${DIM}Read/Creation/Ratio/Status = last ${WINDOW} assistant turn(s). Pass -n N to change. \"Turns\" = all turns in file.${NC}"
    echo ""
    printf "${DIM}%-38s %-6s %-10s %-10s %-8s %s${NC}\n" "Session" "Turns" "Read" "Creation" "Ratio" "Status"
    echo -e "${DIM}${SEP}${SEP}${NC}"

    find "$PROJ_DIR" -maxdepth 1 -name "*.jsonl" -type f 2>/dev/null | sort | while read -r F; do
        SID=$(basename "$F" .jsonl)
        TURNS=$(count_assistant_turns "$F")
        [ "$TURNS" -eq 0 ] 2>/dev/null && continue

        METRICS=$(extract_metrics "$F")
        METRICS_TAIL=$(echo "$METRICS" | tail -n "$WINDOW")
        [ -z "$METRICS_TAIL" ] && continue

        METRICS_R=$(echo "$METRICS_TAIL" | detect_resume)
        TF=$(mktemp 2>/dev/null || echo "/tmp/cc-sess.$$")
        echo "$METRICS_R" | while IFS='|' read -r T C R I O TS RESUME; do
            [ -z "$T" ] && continue
            V=$(verdict "$C" "$R" "$RESUME")
            TOTAL_C=$((${TOTAL_C:-0} + C))
            TOTAL_R=$((${TOTAL_R:-0} + R))
            case "$V" in bad|miss) BAD=$((${BAD:-0} + 1)) ;; esac
            echo "${TOTAL_C}:${TOTAL_R}:${BAD:-0}" > "$TF"
        done

        if [ -f "$TF" ]; then
            IFS=: read -r TOTAL_C TOTAL_R BAD < "$TF"
            rm -f "$TF"

            if [ "$TOTAL_R" -gt 0 ] 2>/dev/null; then
                RATIO=$(awk "BEGIN{printf \"%.2f\", ${TOTAL_C}/${TOTAL_R}}")
            else
                RATIO="inf"
            fi

            if [ "${BAD:-0}" -eq 0 ] 2>/dev/null; then
                STATUS="${GREEN}healthy${NC}"
            elif [ "${BAD:-0}" -le 1 ] 2>/dev/null; then
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
    if [ -n "${CACHE_CATCHER_FROM_CLAUDE_CODE:-}" ]; then
        local self
        self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
        echo -e "${RED}watch is unavailable in Claude Code.${NC}" >&2
        echo "Run the CLI in your own terminal (hooks cannot run a long-lived monitor). Example:" >&2
        echo "  ${self} watch -p ${PROJECT_DIR}" >&2
        echo "If you use a shell alias for this script, run: cd ${PROJECT_DIR} && cache-catcher watch" >&2
        exit 1
    fi

    local TRANSCRIPT
    TRANSCRIPT=$(find_transcript)
    [ -z "$TRANSCRIPT" ] && echo -e "${RED}No transcript found.${NC}" && exit 1

    echo -e "${BOLD}Cache Catcher — Live Monitor${NC} ${DIM}(Ctrl+C to stop)${NC}"
    echo ""

    local LAST_LINES=0
    while true; do
        CURRENT_LINES=$(count_assistant_turns "$TRANSCRIPT")
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
    *)        echo "Unknown command: $CMD" >&2; exit 1 ;;
esac

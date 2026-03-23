#!/bin/bash
# Hooker setup-cron — install/update scheduled tasks from schedules.yml
# Reads .claude/hooker/schedules.yml, generates scheduled entries with
# claude -p, replaces existing entries for this project directory.
#
# Usage: bash setup-cron.sh [path/to/schedules.yml]
# Run from project root or pass config path.
#
# Platform: Linux/macOS (crontab), Windows Git Bash (Task Scheduler via schtasks).

set -euo pipefail

CONFIG="${1:-.claude/hooker/schedules.yml}"
PROJECT_DIR="$(pwd)"

if [ ! -f "$CONFIG" ]; then
    echo "No schedules.yml found at $CONFIG"
    echo "Create .claude/hooker/schedules.yml with:"
    echo ""
    echo "schedules:"
    echo "  - name: nightly-review"
    echo "    cron: \"0 3 * * *\""
    echo "    prompt: \"Review changes, write to .claude/hooker/cron-results/\""
    echo "  - name: complex-task"
    echo "    cron: \"0 6 * * *\""
    echo "    prompt_file: .claude/hooker/prompts/task.md"
    exit 1
fi

# --- Detect platform ---
IS_WINDOWS=false
if [ -n "${WINDIR:-}" ] || uname -s | grep -qi 'mingw\|msys\|cygwin'; then
    IS_WINDOWS=true
fi

# --- Parse schedules from yml ---
NAMES=""
CRONS=""
PROMPTS=""
COUNT=0

CUR_CRON=""
CUR_PROMPT=""
CUR_PROMPT_FILE=""
CUR_NAME=""

flush_entry() {
    [ -z "$CUR_CRON" ] && return
    local CMD_PROMPT=""
    if [ -n "$CUR_PROMPT_FILE" ]; then
        local FULL_PATH="${PROJECT_DIR}/${CUR_PROMPT_FILE}"
        if [ -f "$FULL_PATH" ]; then
            CMD_PROMPT="${FULL_PATH}"
        else
            echo "WARNING: prompt_file not found: $CUR_PROMPT_FILE (schedule: $CUR_NAME)" >&2
            return
        fi
    elif [ -n "$CUR_PROMPT" ]; then
        CMD_PROMPT="INLINE:${CUR_PROMPT}"
    else
        echo "WARNING: no prompt or prompt_file for schedule: $CUR_NAME" >&2
        return
    fi
    COUNT=$((COUNT + 1))
    # Store in temp files (arrays not portable across all bash versions)
    echo "$CUR_NAME" >> "/tmp/hooker_sched_names_$$"
    echo "$CUR_CRON" >> "/tmp/hooker_sched_crons_$$"
    echo "$CMD_PROMPT" >> "/tmp/hooker_sched_prompts_$$"
}

rm -f "/tmp/hooker_sched_names_$$" "/tmp/hooker_sched_crons_$$" "/tmp/hooker_sched_prompts_$$" 2>/dev/null

while IFS= read -r line; do
    case "$line" in
        *"- name:"*)
            flush_entry
            CUR_NAME=$(echo "$line" | sed 's/.*name:[[:space:]]*//' | sed 's/[[:space:]]*$//')
            CUR_CRON="" CUR_PROMPT="" CUR_PROMPT_FILE=""
            ;;
        *"cron:"*)
            CUR_CRON=$(echo "$line" | sed 's/.*cron:[[:space:]]*//' | sed 's/^"//; s/"[[:space:]]*$//')
            ;;
        *"prompt_file:"*)
            CUR_PROMPT_FILE=$(echo "$line" | sed 's/.*prompt_file:[[:space:]]*//' | sed 's/^"//; s/"[[:space:]]*$//')
            ;;
        *"prompt:"*)
            CUR_PROMPT=$(echo "$line" | sed 's/.*prompt:[[:space:]]*//' | sed 's/^"//; s/"[[:space:]]*$//')
            ;;
    esac
done < "$CONFIG"
flush_entry

if [ "$COUNT" -eq 0 ]; then
    echo "No schedules found in $CONFIG"
    rm -f "/tmp/hooker_sched_names_$$" "/tmp/hooker_sched_crons_$$" "/tmp/hooker_sched_prompts_$$" 2>/dev/null
    exit 1
fi

# --- Convert cron expression to schtasks schedule ---
# Handles common patterns: "MIN HOUR * * *" (daily), "MIN HOUR * * DOW" (weekly)
cron_to_schtasks() {
    local CRON="$1" NAME="$2" CMD="$3"
    local MIN HOUR DOM MON DOW
    MIN=$(echo "$CRON" | awk '{print $1}')
    HOUR=$(echo "$CRON" | awk '{print $2}')
    DOM=$(echo "$CRON" | awk '{print $3}')
    MON=$(echo "$CRON" | awk '{print $4}')
    DOW=$(echo "$CRON" | awk '{print $5}')

    local TIME
    TIME=$(printf '%02d:%02d' "$HOUR" "$MIN")

    local TASK_NAME="hooker-${NAME}"

    if [ "$DOW" != "*" ]; then
        # Weekly — map 0-6 to SUN-SAT
        local DAYS=""
        case "$DOW" in
            0) DAYS="SUN" ;; 1) DAYS="MON" ;; 2) DAYS="TUE" ;; 3) DAYS="WED" ;;
            4) DAYS="THU" ;; 5) DAYS="FRI" ;; 6) DAYS="SAT" ;; *) DAYS="$DOW" ;;
        esac
        echo "schtasks /create /tn \"${TASK_NAME}\" /tr \"cmd /c cd /d ${PROJECT_DIR} && ${CMD}\" /sc weekly /d ${DAYS} /st ${TIME} /f"
    elif [ "$DOM" != "*" ]; then
        # Monthly
        echo "schtasks /create /tn \"${TASK_NAME}\" /tr \"cmd /c cd /d ${PROJECT_DIR} && ${CMD}\" /sc monthly /d ${DOM} /st ${TIME} /f"
    else
        # Daily
        echo "schtasks /create /tn \"${TASK_NAME}\" /tr \"cmd /c cd /d ${PROJECT_DIR} && ${CMD}\" /sc daily /st ${TIME} /f"
    fi
}

# --- Install: crontab (Linux/macOS) or schtasks (Windows) ---
if $IS_WINDOWS; then
    echo "Windows detected — using Task Scheduler (schtasks)"
    echo ""

    # Delete existing hooker tasks for this project
    schtasks /query /fo csv 2>/dev/null | grep "hooker-" | while IFS=, read -r TASKNAME _REST; do
        TASKNAME=$(echo "$TASKNAME" | sed 's/"//g')
        schtasks /delete /tn "$TASKNAME" /f 2>/dev/null || true
    done

    # Create new tasks
    LINE_NUM=0
    while IFS= read -r NAME; do
        LINE_NUM=$((LINE_NUM + 1))
        CRON=$(sed -n "${LINE_NUM}p" "/tmp/hooker_sched_crons_$$")
        PROMPT=$(sed -n "${LINE_NUM}p" "/tmp/hooker_sched_prompts_$$")

        # Build claude command
        local_cmd=""
        case "$PROMPT" in
            INLINE:*) local_cmd="claude -p \"${PROMPT#INLINE:}\"" ;;
            *) local_cmd="claude -p \"$(cat "$PROMPT" 2>/dev/null)\"" ;;
        esac

        SCHTASK_CMD=$(cron_to_schtasks "$CRON" "$NAME" "$local_cmd")
        echo "  $SCHTASK_CMD"
        eval "$SCHTASK_CMD" 2>/dev/null && echo "  ✓ Created: $NAME" || echo "  ✗ Failed: $NAME (run as administrator?)"
    done < "/tmp/hooker_sched_names_$$"

    echo ""
    echo "Use 'schtasks /query /fo list | grep hooker' to verify."
else
    # Linux/macOS — crontab
    MARKER_START="# @hooker-start ${PROJECT_DIR}"
    MARKER_END="# @hooker-end ${PROJECT_DIR}"

    # Build entries
    ENTRIES=""
    LINE_NUM=0
    while IFS= read -r NAME; do
        LINE_NUM=$((LINE_NUM + 1))
        CRON=$(sed -n "${LINE_NUM}p" "/tmp/hooker_sched_crons_$$")
        PROMPT=$(sed -n "${LINE_NUM}p" "/tmp/hooker_sched_prompts_$$")

        case "$PROMPT" in
            INLINE:*) ENTRIES="${ENTRIES}${CRON} cd ${PROJECT_DIR} && claude -p \"${PROMPT#INLINE:}\" # hooker:${NAME}
" ;;
            *) ENTRIES="${ENTRIES}${CRON} cd ${PROJECT_DIR} && claude -p \"\$(cat ${PROMPT})\" # hooker:${NAME}
" ;;
        esac
    done < "/tmp/hooker_sched_names_$$"

    CURRENT=$(crontab -l 2>/dev/null || true)

    # Remove existing block for this project
    CLEANED=$(echo "$CURRENT" | awk -v start="$MARKER_START" -v end="$MARKER_END" '
        $0 == start { skip=1; next }
        $0 == end { skip=0; next }
        !skip { print }
    ')

    NEW_CRONTAB="${CLEANED}
${MARKER_START}
${ENTRIES}${MARKER_END}"
    NEW_CRONTAB=$(echo "$NEW_CRONTAB" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba;}')

    echo "$NEW_CRONTAB" | crontab -

    echo "Crontab updated for ${PROJECT_DIR}:"
    echo ""
    echo "$ENTRIES"
    echo "Use 'crontab -l' to verify."
fi

# Cleanup
rm -f "/tmp/hooker_sched_names_$$" "/tmp/hooker_sched_crons_$$" "/tmp/hooker_sched_prompts_$$" 2>/dev/null

echo ""
echo "Run 'setup-cron.sh' again after editing schedules.yml."

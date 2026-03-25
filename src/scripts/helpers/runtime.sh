# Runtime resolution for multi-language match scripts.
# Supports any file extension with configurable runtimes.

# Default runtimes by file extension
_hooker_default_runtime() {
    case "$1" in
        sh|bash) echo "bash" ;;
        py)      echo "python3" ;;
        js|cjs|mjs) echo "node" ;;
        ts|mts)  echo "npx tsx" ;;
        go)      echo "go run" ;;
        php)     echo "php" ;;
        rb)      echo "ruby" ;;
        pl)      echo "perl" ;;
        *)       echo "" ;; # empty = execute directly (binary, unknown)
    esac
}

# Resolve runtime for a file extension.
# Priority: env HOOKER_RUNTIME_<ext> > project runtimes.conf > user runtimes.conf > defaults
_hooker_resolve_runtime() {
    local EXT="$1"

    # 1. Environment variable override (e.g. HOOKER_RUNTIME_py=python3.12)
    eval "local ENV_VAL=\${HOOKER_RUNTIME_${EXT}:-}"
    [ -n "$ENV_VAL" ] && echo "$ENV_VAL" && return

    # 2. Project runtimes.conf
    local PROJECT_CONF="${HOOKER_CWD:-.}/.claude/hooker/runtimes.conf"
    if [ -f "$PROJECT_CONF" ]; then
        local VAL
        VAL=$(grep "^${EXT}=" "$PROJECT_CONF" 2>/dev/null | head -1 | cut -d= -f2-)
        [ -n "$VAL" ] && echo "$VAL" && return
    fi

    # 3. User runtimes.conf
    local USER_CONF="${HOME}/.claude/hooker/runtimes.conf"
    if [ -f "$USER_CONF" ]; then
        local VAL
        VAL=$(grep "^${EXT}=" "$USER_CONF" 2>/dev/null | head -1 | cut -d= -f2-)
        [ -n "$VAL" ] && echo "$VAL" && return
    fi

    # 4. Built-in default
    _hooker_default_runtime "$EXT"
}

# Find match script for a hook event in a directory (any language).
# Shell (.sh) has priority for backward compat, then common langs, then any.
_hooker_find_match() {
    local DIR="$1" HOOK="$2"

    # Shell first (backward compat)
    [ -f "${DIR}/${HOOK}.match.sh" ] && echo "${DIR}/${HOOK}.match.sh" && return

    # Common extensions
    for EXT in py js ts go php rb pl; do
        [ -f "${DIR}/${HOOK}.match.${EXT}" ] && echo "${DIR}/${HOOK}.match.${EXT}" && return
    done

    # Fallback: any other extension
    for F in "${DIR}/${HOOK}".match.*; do
        [ -f "$F" ] && echo "$F" && return
    done

    return 1
}

# Execute a match script with the appropriate runtime.
# Reads from stdin, writes to stdout. Caller handles exit codes.
_hooker_run_match() {
    local SCRIPT="$1"
    local EXT="${SCRIPT##*.}"
    local RUNTIME
    RUNTIME=$(_hooker_resolve_runtime "$EXT")

    if [ -z "$RUNTIME" ]; then
        # No runtime = execute directly (binary or self-executing)
        "$SCRIPT"
    elif [ "$EXT" = "sh" ] || [ "$EXT" = "bash" ]; then
        # Shell: execute directly (has shebang, is +x)
        "$SCRIPT"
    else
        # Non-shell: invoke through runtime
        # shellcheck disable=SC2086
        $RUNTIME "$SCRIPT"
    fi
}

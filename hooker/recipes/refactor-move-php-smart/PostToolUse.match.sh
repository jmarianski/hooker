#!/bin/bash
# Refactor Move PHP (smart) — namespace/use rewriting after mv
# PostToolUse hook: fires after Bash tool completes
# Uses phpactor class:move if available, falls back to composer.json PSR-4 + sed.
source "${HOOKER_HELPERS}"

INPUT=$(cat)

# Only act on Bash tool
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" = "Bash" ] || exit 1

# Extract command
CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Strip leading env vars (VAR=val), cd chains (cd dir &&), and mv flags
MV_CMD=$(echo "$CMD" | sed 's/^[^;|&]*&&[[:space:]]*//' | sed 's/^[A-Z_]*=[^[:space:]]*[[:space:]]*//')
MV_CMD=$(echo "$MV_CMD" | sed 's/^[A-Z_]*=[^[:space:]]*[[:space:]]*//')
MV_CMD=$(echo "$MV_CMD" | sed 's/^git[[:space:]]\+mv/mv/')
echo "$CMD" | grep -q 'HOOKER_NO_REFACTOR=1' && exit 1
MV_ARGS=$(echo "$MV_CMD" | sed 's/^mv[[:space:]]\+//; s/^-[a-zA-Z]\+[[:space:]]*//g; s/^--[a-zA-Z-]\+[[:space:]]*//g')

# Detect: mv old.php new.php (or directory move)
OLD_PATH=$(echo "$MV_ARGS" | sed -n 's/^\([^[:space:]]\+\)[[:space:]]\+.*/\1/p')
NEW_PATH=$(echo "$MV_ARGS" | sed -n 's/^[^[:space:]]\+[[:space:]]\+\([^[:space:]]\+\)/\1/p')
[ -z "$OLD_PATH" ] || [ -z "$NEW_PATH" ] && exit 1

# Must be a .php file OR a directory containing .php files
is_php_file() { echo "$1" | grep -q '\.php$'; }
has_php_files() { [ -d "$1" ] && find "$1" -name '*.php' 2>/dev/null | head -1 | grep -q .; }

if is_php_file "$OLD_PATH"; then
    if [ -d "$NEW_PATH" ]; then
        NEW_PATH="${NEW_PATH%/}/$(basename "$OLD_PATH")"
    fi
elif [ -d "$NEW_PATH" ] && ! [ -d "$OLD_PATH" ]; then
    has_php_files "$NEW_PATH" || exit 1
else
    exit 1
fi

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load messages
MSG_UPDATED=$(sed -n 's/^updated:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_REFS=$(sed -n 's/^no_refs:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
MSG_NO_PHPACTOR=$(sed -n 's/^no_phpactor:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")

# --- Derive FQCN from file path + composer.json PSR-4 ---
# Maps file path to fully qualified class name using PSR-4 autoload rules
path_to_fqcn() {
    local FILE_PATH="$1"
    [ ! -f "composer.json" ] && return 1

    # Extract PSR-4 mappings: "Namespace\\" : "dir/"
    # Output: dir/<TAB>Namespace\ (longest dir first for correct matching)
    local MAPPINGS
    MAPPINGS=$(sed -n '/"psr-4"/,/}/{ /"/{ s/.*"\([^"]*\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2\t\1/p; }; }' composer.json \
        | sed 's|\\\\|\\|g' | sort -t'	' -k1,1r)

    [ -z "$MAPPINGS" ] && return 1

    # Find matching PSR-4 prefix
    echo "$MAPPINGS" | while IFS='	' read -r DIR NS; do
        DIR=$(echo "$DIR" | sed 's|/$||')
        case "$FILE_PATH" in
            ${DIR}/*)
                local REL="${FILE_PATH#${DIR}/}"
                REL=$(echo "$REL" | sed 's|\.php$||; s|/|\\|g')
                echo "${NS}${REL}"
                return 0
                ;;
        esac
    done
}

# --- Try phpactor first ---
if command -v phpactor >/dev/null 2>&1 && [ -f "composer.json" ]; then
    if is_php_file "$OLD_PATH"; then
        # phpactor class:move works with file paths
        RESULT=$(phpactor class:move "$OLD_PATH" "$NEW_PATH" 2>&1) && {
            # Count affected files from phpactor output
            COUNT=$(echo "$RESULT" | grep -c 'updated\|moved\|renamed' 2>/dev/null || echo "1")
            MSG=$(echo "$MSG_UPDATED" | sed "s/{count}/$COUNT/g")
            inject "Refactor Move (phpactor): ${MSG}"
            exit 0
        }
    fi
fi

# --- Fallback: composer.json PSR-4 + sed ---
if ! is_php_file "$OLD_PATH"; then
    inject "phpactor not available and directory moves cannot use sed fallback. Install phpactor: composer global require phpactor/phpactor"
    exit 0
fi

OLD_FQCN=$(path_to_fqcn "$OLD_PATH")
NEW_FQCN=$(path_to_fqcn "$NEW_PATH")

if [ -z "$OLD_FQCN" ] || [ -z "$NEW_FQCN" ]; then
    inject "File moved but could not derive namespaces from composer.json PSR-4. Check namespace/use statements manually."
    exit 0
fi

[ "$OLD_FQCN" = "$NEW_FQCN" ] && exit 1

# Escape backslashes for sed
OLD_ESCAPED=$(echo "$OLD_FQCN" | sed 's|\\|\\\\|g')
NEW_ESCAPED=$(echo "$NEW_FQCN" | sed 's|\\|\\\\|g')

# Update namespace declaration in moved file
OLD_NS=$(echo "$OLD_FQCN" | sed 's|\\[^\\]*$||')
NEW_NS=$(echo "$NEW_FQCN" | sed 's|\\[^\\]*$||')
OLD_NS_ESCAPED=$(echo "$OLD_NS" | sed 's|\\|\\\\|g')
NEW_NS_ESCAPED=$(echo "$NEW_NS" | sed 's|\\|\\\\|g')

if [ -f "$NEW_PATH" ] && [ "$OLD_NS" != "$NEW_NS" ]; then
    _hooker_sed_i "s|namespace ${OLD_NS_ESCAPED};|namespace ${NEW_NS_ESCAPED};|g" "$NEW_PATH" 2>/dev/null
fi

# Find PHP files referencing old FQCN
OLD_GREP=$(echo "$OLD_FQCN" | sed 's|\\|\\\\|g')
AFFECTED_FILES=$(grep -rl "${OLD_GREP}" --include='*.php' . 2>/dev/null \
    | grep -v vendor | grep -v '.git/' || true)

[ -z "$AFFECTED_FILES" ] && {
    inject "$MSG_NO_REFS"
    exit 0
}

COUNT=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    if grep -q "${OLD_GREP}" "$file" 2>/dev/null; then
        # Update use statements and fully qualified references
        _hooker_sed_i "s|${OLD_ESCAPED}|${NEW_ESCAPED}|g" "$file" 2>/dev/null
        COUNT=$((COUNT + 1))
    fi
done <<< "$AFFECTED_FILES"

if [ "$COUNT" -gt 0 ]; then
    MSG=$(echo "$MSG_UPDATED" | sed "s/{count}/$COUNT/g")
    inject "Refactor Move (sed/PSR-4 fallback): ${MSG}"
else
    inject "$MSG_NO_REFS"
fi
exit 0

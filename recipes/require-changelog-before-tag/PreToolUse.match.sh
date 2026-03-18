#!/bin/bash
# Block git tag / push --tags unless CHANGELOG.md was updated
source "${HOOKER_HELPERS}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSGS_FILE=".claude/hooker/require-changelog-before-tag.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1 || echo "$2"
}

INPUT=$(cat)
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" != "Bash" ] && exit 1

CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Only care about tagging or pushing tags
echo "$CMD" | grep -q 'git[[:space:]]\+\(tag[[:space:]]\|push[[:space:]]\+.*--tags\)' || exit 1

# Allow if CHANGELOG.md is staged
git diff --cached --name-only 2>/dev/null | grep -q 'CHANGELOG.md' && exit 1

# Allow if CHANGELOG.md was in the last commit
git log -1 --name-only --pretty=format: 2>/dev/null | grep -q 'CHANGELOG.md' && exit 1

deny "$(yml_get no_changelog 'Update CHANGELOG.md before tagging a release.')"
exit 0

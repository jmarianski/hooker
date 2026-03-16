#!/bin/bash
# Block git tag / push --tags unless CHANGELOG.md was updated
source "${HOOKER_HELPERS}"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"\K[^"]+' || true)
[ "$TOOL" != "Bash" ] && exit 1

CMD=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"\K[^"]+' || true)

# Only care about tagging or pushing tags
echo "$CMD" | grep -qP 'git\s+(tag\s|push\s+.*--tags)' || exit 1

# Allow if CHANGELOG.md is staged
git diff --cached --name-only 2>/dev/null | grep -q 'CHANGELOG.md' && exit 1

# Allow if CHANGELOG.md was in the last commit
git log -1 --name-only --pretty=format: 2>/dev/null | grep -q 'CHANGELOG.md' && exit 1

deny "Update CHANGELOG.md before tagging a release."
exit 0

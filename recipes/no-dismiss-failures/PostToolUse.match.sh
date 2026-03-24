#!/bin/bash
# No Dismiss Failures — remind agent to investigate test/lint failures
# PostToolUse hook: fires after Bash tool with test/lint commands
source "${HOOKER_HELPERS}"

INPUT=$(cat)

# Only act on Bash tool
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ "$TOOL" = "Bash" ] || exit 1

# Check if it's a test/lint command
CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
echo "$CMD" | grep -qi "test\|lint\|check\|tsc.*noEmit\|mypy\|pylint\|flake8\|eslint\|prettier.*check\|rubocop\|clippy\|go vet\|shellcheck" || exit 1

# Only fire if tool had non-zero exit code
echo "$INPUT" | grep -q '"exit_code"[[:space:]]*:[[:space:]]*[1-9]' || exit 1

# Load message
RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
MSG=$(sed -n 's/^reminder:[[:space:]]*"\(.*\)"/\1/p' "${RECIPE_DIR}/messages.yml")
[ -z "$MSG" ] && MSG="Test/lint failed. Investigate root cause, fix, or explain to user."

inject "$MSG"
exit 0

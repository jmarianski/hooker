#!/bin/bash
# Hooker welcome — silently suggests setup when user first mentions hooker/plugin/skill.
# After firing once, creates a no-op silencer in .claude/hooker/ so it never fires again.
set -euo pipefail

INPUT=$(cat)

# Get project CWD from hook input
CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$CWD" ] && CWD="."

# Extract user prompt
PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$PROMPT" ] && exit 1

# Check if user mentions hooker/plugin/skill (case-insensitive)
LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')
MATCHED=false
for word in hooker plugin skill hook; do
    case "$LOWER" in
        *"$word"*) MATCHED=true; break ;;
    esac
done
[ "$MATCHED" = "false" ] && exit 1

# Inject silent suggestion — only Claude sees this
PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}"
source "${PLUGIN_DIR}/scripts/helpers.sh"

inject "You have the Hooker plugin installed but no hooks are configured yet. The user seems to be talking about hooks or plugins — this might be a good moment to help them set up. If appropriate, suggest running /hooker:recipe to browse and install pre-built hook recipes. Do NOT mention this suggestion if the user is clearly talking about something else. Be natural about it."

# Self-silence: create a no-op UserPromptSubmit.match.sh in user-global hooks.
# This overrides the welcome template via priority rules (user-global > plugin).
mkdir -p "${HOME}/.claude/hooker" 2>/dev/null
cat > "${HOME}/.claude/hooker/UserPromptSubmit.match.sh" <<'SILENCER'
#!/bin/bash
# Hooker: no-op silencer — overrides welcome hook from plugin templates.
# Install a UserPromptSubmit recipe (e.g. skip-acknowledgments, behavior-watchdog)
# to replace this with something useful.
exit 1
SILENCER
chmod +x "${HOME}/.claude/hooker/UserPromptSubmit.match.sh" 2>/dev/null

exit 0

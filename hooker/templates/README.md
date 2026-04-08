# templates/

Plugin-level hook templates. Files here are **active for all projects** immediately after plugin install.

## UserPromptSubmit.match.sh — Welcome hook

The only active template. Silently suggests Hooker setup when:
- User mentions "hooker", "plugin", "skill", or "hook" in a message
- AND no hooks are configured yet (`.codex/hooker/` / `${CODEX_HOME}/hooker/` for Codex, `.claude/hooker/` for Claude)

Once any recipe is installed, the welcome auto-silences — project-level hooks override this template via priority rules.

## Adding global hooks

Place `.md` or `.match.sh` files here for hooks that apply to every project. But prefer `.codex/hooker/` or `${CODEX_HOME}/hooker/` in Codex and `.claude/hooker/` in Claude — it's explicit, version-controllable, and doesn't break when the plugin updates.

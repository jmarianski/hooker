---
description: "Show active Hooker hooks and their templates"
---

# Hooker Status

Show the user which hooks are active (have templates/scripts) and which are inactive.

## Steps

1. Check for plugin-level files in `${CLAUDE_PLUGIN_ROOT}/templates/` — list all `*.md` and `*.match.sh` files
2. Check for user-global overrides in `~/.claude/hooker/` — list all `*.md` and `*.match.sh` files
3. Check for project-level overrides in `.claude/hooker/` — list all `*.md` and `*.match.sh` files
3. For each of the 21 hooks, show status:

Format output as a table:

```
Hook                 | Status    | Source           | Mode        | Type
---------------------|-----------|------------------|-------------|--------
SessionStart         | inactive  | -                | -           | -
Stop                 | ACTIVE    | plugin/templates | conditional | remind
PreToolUse           | ACTIVE    | .claude/hooker   | dynamic     | (script)
SubagentStart        | ACTIVE    | .claude/hooker   | static      | inject
...
```

**Mode** detection:
- `.md` exists, no `.match.sh` → `static`
- `.md` + `.match.sh` both exist → `conditional`
- `.match.sh` only (no `.md`) → `dynamic`

**Type**: Read from `.md` frontmatter `type:` field, or `(script)` if dynamic mode

**Source**: `plugin/templates` (default), `~/.claude/hooker` (user-global), or `.claude/hooker` (project override)

Mark active hooks clearly, inactive ones as dimmed/dash.

## All 21 hook names (for completeness check)
SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure, Notification, SubagentStart, SubagentStop, Stop, TeammateIdle, TaskCompleted, InstructionsLoaded, ConfigChange, WorktreeCreate, WorktreeRemove, PreCompact, PostCompact, Elicitation, ElicitationResult, SessionEnd

---
description: "Show active Hooker hooks and their templates"
---

# Hooker Status

Show the user which hooks are active (have templates/scripts) and which are inactive.

## Steps

1. Check for plugin-level files in `${CLAUDE_PLUGIN_ROOT}/templates/` — list all `*.md` and `*.match.sh` files
2. Check for user-global overrides in `~/.claude/hooker/` — list all `*.md` and `*.match.sh` files
3. Check for project-level overrides in `.claude/hooker/` — list all `*.md` and `*.match.sh` files
4. For each hook event, show status:

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

## Base hook events (in plugin hooks.json, CC >= 2.1.68)
SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure, Notification, SubagentStart, SubagentStop, Stop, TeammateIdle, TaskCompleted, ConfigChange, WorktreeCreate, WorktreeRemove, PreCompact, Elicitation, ElicitationResult, SessionEnd, Setup

## Overflow hook events (version-gated, added via settings.json)
InstructionsLoaded (CC >= 2.1.69), StopFailure (CC >= 2.1.78), PostCompact (CC >= 2.1.78), CwdChanged (CC >= 2.1.83), FileChanged (CC >= 2.1.83), TaskCreated (CC >= 2.1.84), PermissionDenied (CC >= 2.1.89)

---
description: "Show active Hooker hooks and their templates"
---

# Hooker Status

Show the user which hooks are active (have templates) and which are inactive.

## Steps

1. Check for plugin-level templates in `${CLAUDE_PLUGIN_ROOT}/templates/` — list all `*.md` files
2. Check for project-level overrides in `.claude/hooker/` — list all `*.md` files
3. For each of the 21 hooks, show status:

Format output as a table:

```
Hook                 | Status    | Source              | Type
---------------------|-----------|---------------------|--------
SessionStart         | inactive  | -                   | -
Stop                 | ACTIVE    | plugin/templates    | remind
PreToolUse           | ACTIVE    | .claude/hooker      | deny
...
```

- **Source**: `plugin/templates` (default) or `.claude/hooker` (project override)
- **Type**: Read from frontmatter `type:` field (inject/remind/block/allow/deny/context)
- Mark active hooks clearly, inactive ones as dimmed/dash

## All 21 hook names (for completeness check)
SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure, Notification, SubagentStart, SubagentStop, Stop, TeammateIdle, TaskCompleted, InstructionsLoaded, ConfigChange, WorktreeCreate, WorktreeRemove, PreCompact, PostCompact, Elicitation, ElicitationResult, SessionEnd

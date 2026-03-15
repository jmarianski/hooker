---
description: "Configure Hooker - logging, templates, hook status"
args: "[on|off|logs]"
---

# Hooker Configuration

You are managing the Hooker plugin configuration. Read the current state and help the user configure it.

## Current State

1. Read `.claude/hooker.json` if it exists (project-level config)
2. List all active hooks:
   - Plugin defaults: check `${CLAUDE_PLUGIN_ROOT}/templates/` for `*.md` and `*.match.sh` files
   - Project overrides: check `.claude/hooker/` for `*.md` and `*.match.sh` files

## Available Actions

Based on user's argument or ask them what they want:

### `logs` or logging configuration
- Toggle logging in `.claude/hooker.json`:
  ```json
  { "logs": true }
  ```
- Log file location: `~/.cache/hooker/hooker.log`
- Show recent log entries if logs exist

### `on` / `off` (no args = show status)
- Show which hooks have templates/scripts (active) vs nothing (inactive/passthrough)
- Group by category:
  - **Session**: SessionStart, SessionEnd, InstructionsLoaded
  - **Tools**: PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest
  - **Flow**: UserPromptSubmit, Stop, TaskCompleted
  - **Agents**: SubagentStart, SubagentStop, TeammateIdle
  - **Compact**: PreCompact, PostCompact
  - **Config**: ConfigChange, WorktreeCreate, WorktreeRemove
  - **MCP**: Elicitation, ElicitationResult
  - **Other**: Notification

## Three modes of operation (for user education)

| Mode | Files | Behavior |
|------|-------|----------|
| **Static** | `.md` only | Always fires, content from template |
| **Conditional** | `.md` + `.match.sh` (no output) | Match script decides IF, template decides WHAT |
| **Dynamic** | `.match.sh` (with output) | Script handles everything — uses helpers |

## Action types reference
| Type | Behavior | Best for |
|------|----------|----------|
| `inject` | Injects into Claude's context, hidden by default | SessionStart, PreCompact, SubagentStart |
| `remind` | Blocks stop to remind, loop-safe | Stop |
| `block` | Always blocks with reason | UserPromptSubmit (guardrails) |
| `warn` | Shows warning but doesn't block | PreToolUse, PostToolUse |
| `allow` | Auto-allows tool use | PreToolUse |
| `deny` | Denies tool use | PreToolUse |
| `ask` | Escalates to user for decision | PreToolUse |
| `context` | Adds additionalContext JSON | PostToolUse |

## Helpers available in match scripts
After `source "${HOOKER_HELPERS}"`:
- `warn "msg"`, `deny "msg"`, `allow "msg"`, `ask "msg"`, `block "msg"`, `remind "msg"`
- `inject "text"`, `context "text"`, `visible "text"`
- `load_md "file.md"` — loads file as hidden content (Claude sees, user doesn't)
- `<hidden>...</hidden>` tags — hide parts of warn/deny/block messages from user
- `<visible>...</visible>` tags — show parts of inject templates to user
- Env vars: `$HOOKER_EVENT`, `$HOOKER_TRANSCRIPT`, `$HOOKER_CWD`, `$HOOKER_HELPERS`

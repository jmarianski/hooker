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
| Type | Visibility | Behavior | Best for |
|------|------------|----------|----------|
| `inject` | **hidden** | Injects into Claude's context via XML trick | SessionStart, PreCompact, SubagentStart |
| `remind` | **visible** | Blocks stop with visible reminder, loop-safe | Stop |
| `block` | **visible** | Always blocks with visible reason | UserPromptSubmit (guardrails) |
| `warn` | **visible** | Shows warning but doesn't block | PreToolUse, PostToolUse |
| `allow` | **visible** | Auto-allows tool use | PreToolUse |
| `deny` | **visible** | Denies tool use | PreToolUse |
| `ask` | **visible** | Escalates to user for decision | PreToolUse |
| `context` | **visible** | Adds additionalContext JSON | PostToolUse |

**Only `inject` supports hidden content.** All other types return JSON — Claude Code renders their reason/message as plaintext, so XML trick cannot escape JSON strings.

## Helpers available in match scripts
After `source "${HOOKER_HELPERS}"`:
- `warn "msg"`, `deny "msg"`, `allow "msg"`, `ask "msg"`, `block "msg"`, `remind "msg"` — always visible
- `inject "text"` — hidden from user (XML trick), only Claude sees
- `context "text"`, `visible "text"`
- `load_md "file.md"` — only useful inside `inject()`, not inside JSON helpers
- `<visible>...</visible>` tags — show parts of inject templates to user
- `<hidden>` tags in JSON helpers are **stripped** (content discarded, not hidden)
- Env vars: `$HOOKER_EVENT`, `$HOOKER_TRANSCRIPT`, `$HOOKER_CWD`, `$HOOKER_HELPERS`

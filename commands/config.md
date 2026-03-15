---
description: "Configure Hooker - logging, templates, hook status"
args: "[on|off|logs]"
---

# Hooker Configuration

You are managing the Hooker plugin configuration. Read the current state and help the user configure it.

## Current State

1. Read `.claude/hooker.json` if it exists (project-level config)
2. List all active templates:
   - Plugin defaults: check `${CLAUDE_PLUGIN_ROOT}/templates/` for `*.md` files
   - Project overrides: check `.claude/hooker/` for `*.md` files

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
- Show which hooks have templates (active) vs no template (inactive/passthrough)
- Group by category:
  - **Session**: SessionStart, SessionEnd, InstructionsLoaded
  - **Tools**: PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest
  - **Flow**: UserPromptSubmit, Stop, TaskCompleted
  - **Agents**: SubagentStart, SubagentStop, TeammateIdle
  - **Compact**: PreCompact, PostCompact
  - **Config**: ConfigChange, WorktreeCreate, WorktreeRemove
  - **MCP**: Elicitation, ElicitationResult
  - **Other**: Notification

### Template types reference (for user education)
Show the user available frontmatter `type` values:
| Type | Behavior | Best for |
|------|----------|----------|
| `inject` | Injects content into Claude's context (default) | SessionStart, PreCompact, SubagentStart |
| `remind` | Blocks stop to show reminder, prevents loops | Stop |
| `block` | Always blocks with reason | UserPromptSubmit (guardrails) |
| `allow` | Auto-allows PreToolUse | PreToolUse (skip permission) |
| `deny` | Denies PreToolUse | PreToolUse (block dangerous tools) |
| `context` | Adds as additionalContext JSON | PostToolUse, PostToolUseFailure |

## All 21 hooks reference
| Hook | Can block? | Matcher matches on |
|------|-----------|-------------------|
| SessionStart | No | startup, resume, clear, compact |
| UserPromptSubmit | Yes | - |
| PreToolUse | Yes | Tool name (Bash, Edit, Write...) |
| PermissionRequest | Yes | Tool name |
| PostToolUse | Yes* | Tool name |
| PostToolUseFailure | No | Tool name |
| Notification | No | permission_prompt, idle_prompt, auth_success |
| SubagentStart | No | Agent type |
| SubagentStop | Yes | Agent type |
| Stop | Yes | - |
| TeammateIdle | Yes | - |
| TaskCompleted | Yes | - |
| InstructionsLoaded | No | - |
| ConfigChange | Yes | user_settings, project_settings... |
| WorktreeCreate | Yes | - |
| WorktreeRemove | No | - |
| PreCompact | No | manual, auto |
| PostCompact | No | manual, auto |
| Elicitation | Yes | MCP server name |
| ElicitationResult | Yes | MCP server name |
| SessionEnd | No | clear, logout, prompt_input_exit... |

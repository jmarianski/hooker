---
description: "Configure Hooker - logging, templates, hook status"
args: "[on|off|logs | natural language request]"
---

# Hooker Configuration

You are managing the Hooker plugin configuration. Read the current state, help the user configure hooks, edit existing ones, or troubleshoot issues.

## Hook file locations (priority order)

1. **Project-level**: `.claude/hooker/` — overrides everything, version-controllable
2. **User-global**: `~/.claude/hooker/` — applies to all projects unless overridden
3. **Plugin defaults**: `${HOOKER_PLUGIN_DIR}`/`templates/` — ships with plugin

Before editing or troubleshooting, detect the host runtime:
- `.claude-plugin/plugin.json` => Claude Code
- `.codex-plugin/plugin.json` => Codex

Only reason about hooks and recipes supported by that runtime.

When the user asks to edit/fix/disable a hook, check ALL three locations to find where it lives.

## Current State

1. Read `.claude/hooker.json` if it exists (project-level config)
2. List all active hooks from all three locations above

## Available Actions

Based on user's argument or ask them what they want:

### Natural language requests
If user describes what they want (e.g. "fix the stop hook", "disable remind", "stop asking about tests"):
1. Find the relevant hook file(s) — check all three locations
2. Read the file to understand current behavior
3. Edit it to match what the user wants
4. If it has a `messages.yml`, edit messages there instead of the script
5. **Cross-platform**: all scripts must work on Linux, macOS, and Windows (Git Bash).
   No `grep -P`, `tac`, `python3`, `perl`. Use POSIX grep/sed/awk only.
   See `/hooker:recipe` for full cross-platform rules.

### `logs` or logging configuration
- Toggle logging in `.claude/hooker.json`:
  ```json
  { "logs": true }
  ```
- Log file location: `~/.cache/hooker/hooker.log`
- Show recent log entries if logs exist

### `on` / `off` (no args = show status)
- Show which hooks have templates/scripts (active) vs nothing (inactive/passthrough)
- Group by category for the current runtime:
  - **Session**: SessionStart, SessionEnd, Setup (+InstructionsLoaded CC>=2.1.69)
  - **Tools**: PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest (+PermissionDenied CC>=2.1.89)
  - **Flow**: UserPromptSubmit, Stop, TaskCompleted (+StopFailure CC>=2.1.78, +TaskCreated CC>=2.1.84)
  - **Agents**: SubagentStart, SubagentStop, TeammateIdle
  - **Compact**: PreCompact (+PostCompact CC>=2.1.78)
  - **Config**: ConfigChange, WorktreeCreate, WorktreeRemove (+CwdChanged, +FileChanged CC>=2.1.83)
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

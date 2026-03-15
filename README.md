# Hooker - Universal Hook Injection Framework for Claude Code

Inject custom prompts, reminders, and context into any of Claude Code's 21 hook events via simple template files.

## Installation

```bash
claude --plugin-dir /path/to/hooker
```

## How It Works

```
Any hook event fires (e.g., Stop, PreToolUse, SessionStart...)
    ↓
inject.sh checks for template: .claude/hooker/{EventName}.md
    ↓
Falls back to: plugin/templates/{EventName}.md
    ↓
No template? → no-op (passthrough)
    ↓
Template found? → reads frontmatter type, executes action
```

## Template Format

```markdown
---
type: remind
---
Your content here.
```

### Action Types

| Type | Behavior | Best for |
|------|----------|----------|
| `inject` | Injects into Claude's context (default) | SessionStart, PreCompact |
| `remind` | Blocks stop to remind, loop-safe | Stop |
| `block` | Always blocks with reason | UserPromptSubmit (guardrails) |
| `warn` | Shows warning but doesn't block | PreToolUse, PostToolUse |
| `allow` | Auto-allows tool use | PreToolUse |
| `deny` | Denies tool use | PreToolUse |
| `ask` | Escalates to user for decision | PreToolUse |
| `context` | Adds additionalContext JSON | PostToolUse |

## Commands

| Command | Description |
|---------|-------------|
| `/hooker:config` | Configure logging and view hook reference |
| `/hooker:status` | Show which hooks are active |
| `/hooker:enable` | Create a template to enable a hook |

## Project Overrides

Create `.claude/hooker/{HookName}.md` to override plugin defaults per project:

```bash
mkdir -p .claude/hooker
# Or use: /hooker:enable Stop remind
```

## All 21 Hooks

| Category | Hooks |
|----------|-------|
| Session | SessionStart, SessionEnd, InstructionsLoaded |
| Tools | PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest |
| Flow | UserPromptSubmit, Stop, TaskCompleted |
| Agents | SubagentStart, SubagentStop, TeammateIdle |
| Compact | PreCompact, PostCompact |
| Config | ConfigChange, WorktreeCreate, WorktreeRemove |
| MCP | Elicitation, ElicitationResult |
| Other | Notification |

## License

MIT

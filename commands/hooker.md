---
description: "Hooker — universal hook injection framework. Main entry point."
args: "[description of what user wants]"
---

# Hooker

You are the main entry point for the Hooker plugin — a universal hook injection framework for Claude Code.

## With arguments
If the user provided a description of what they want (e.g. `/hooker remind me about docs`, `/hooker block deploys on fridays`), go directly to creating it:
1. Figure out which hook event(s) are needed
2. Decide the best mode (static template, conditional, or dynamic match script)
3. Create the files in `.claude/hooker/` — write the match script and/or template
4. Test it
5. This is the same flow as `/hooker:enable` but skipping the menu

## Without arguments
Show a quick status overview and ask what the user wants.

### 1. Show overview
Scan for active hooks:
- Plugin defaults: `${CLAUDE_PLUGIN_ROOT}/templates/` — list `*.md` and `*.match.sh`
- Project overrides: `.claude/hooker/` — list `*.md` and `*.match.sh`

Show a compact summary like:
```
Hooker v0.3.0 — 21 hooks registered, N active

Active hooks:
  Stop         → remind (remind-to-update-docs)
  SubagentStart → dynamic (agent-gets-claude-context)

Available recipes:
  remind-to-update-docs      — Reminds about docs/tests when stopping after file changes
  agent-gets-claude-context  — Injects CLAUDE.md + MEMORY.md into subagents
```

Read `${CLAUDE_PLUGIN_ROOT}/recipes/*/recipe.json` for recipe listing.

### 2. Ask what they want
Offer options:
- **"Chcę nowy hook"** → ask what they want to achieve, then create files in `.claude/hooker/`
- **"Zainstaluj recepturę"** → delegate to `/hooker:recipe` flow
- **"Pokaż status"** → detailed status table (like `/hooker:status`)
- **"Konfiguracja"** → logging, reference (like `/hooker:config`)

## Reference for creating hooks

### Three modes
| Mode | Files | Behavior |
|------|-------|----------|
| Static | `.md` only | Always fires, content from template |
| Conditional | `.md` + `.match.sh` (no output) | Script decides IF, template decides WHAT |
| Dynamic | `.match.sh` (with output) | Script handles everything via helpers |

### 8 action types (for .md templates)
| Type | Behavior |
|------|----------|
| `inject` | Injects into Claude's context, hidden (default) |
| `remind` | Blocks stop with reminder, loop-safe |
| `block` | Always blocks with reason |
| `warn` | Warning, doesn't block |
| `allow` | Auto-allows tool use |
| `deny` | Denies tool use |
| `ask` | Escalates to user |
| `context` | Adds additionalContext JSON |

### Helpers (for .match.sh scripts)
After `source "${HOOKER_HELPERS}"`:
- `warn "msg"`, `deny "msg"`, `allow "msg"`, `ask "msg"`, `block "msg"`, `remind "msg"`
- `inject "text"`, `context "text"`, `visible "text"`
- `load_md "file.md"` — loads file as hidden content
- `<hidden>...</hidden>` — hide parts of JSON messages from user
- `<visible>...</visible>` — show parts of inject templates to user
- Env vars: `$HOOKER_EVENT`, `$HOOKER_TRANSCRIPT`, `$HOOKER_CWD`, `$HOOKER_HELPERS`

### All 21 hooks
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

### Installing a recipe
1. List: `ls ${CLAUDE_PLUGIN_ROOT}/recipes/`
2. Read: `cat ${CLAUDE_PLUGIN_ROOT}/recipes/{name}/recipe.json`
3. Copy hook files to `.claude/hooker/`
4. `chmod +x` any `.match.sh` files
5. Warn if files already exist in `.claude/hooker/`

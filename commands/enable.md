---
description: "Enable a hook by creating its template and/or match script"
args: "<HookName> [type]"
---

# Enable a Hooker Hook

Create a template file and/or match script for the specified hook in `.claude/hooker/`.

## Arguments
- `HookName` (required): One of the 21 hook event names
- `type` (optional): Template type — `inject`, `remind`, `block`, `warn`, `allow`, `deny`, `ask`, `context`

## Architecture — THREE modes of operation

### Mode 1: Template only (`.md`, no `.match.sh`)
Static rule — always fires, content from template.
```
.claude/hooker/SessionStart.md  → always injects content on session start
```

### Mode 2: Template + match script (`.md` + `.match.sh` without output)
Conditional rule — match script decides IF, template decides WHAT.
```
.claude/hooker/Stop.md          → content to show
.claude/hooker/Stop.match.sh    → exit 0 if files were edited, else exit 1
```

### Mode 3: Standalone match script (`.match.sh` with output, no `.md` needed)
Full dynamic control — script decides everything. Uses helpers for output.
**This is the most powerful mode.** The script can read files, check state, build messages dynamically.
```
.claude/hooker/SubagentStart.match.sh  → reads CLAUDE.md, injects it
```

## Helpers library

Match scripts can `source "${HOOKER_HELPERS}"` to get pre-built functions:

**JSON responses (visible to user by default):**
| Helper | Effect |
|--------|--------|
| `warn "msg"` | Warning, doesn't block |
| `deny "msg"` | Denies tool use (PreToolUse) |
| `allow "msg"` | Auto-allows tool use |
| `ask "msg"` | Escalates to user for decision |
| `block "msg"` | Blocks action (stop/prompt) |
| `remind "msg"` | Blocks stop with reminder |

**Context injection (hidden from user, only Claude sees):**
| Helper | Effect |
|--------|--------|
| `inject "text"` | Injects text into Claude's context (XML trick) |
| `context "text"` | Adds as additionalContext JSON |
| `visible "text"` | Outputs text visible to user |
| `load_md "file.md"` | Loads file as `<hidden>` content (Claude sees, user doesn't) |

**Visibility tags in messages:**
- `<hidden>...</hidden>` — inside warn/deny/block: hidden from user, only Claude sees
- `<visible>...</visible>` — inside inject templates (.md): shown to user
- `load_md "file.md"` — wraps file content in `<hidden>` automatically

**Environment variables (no JSON parsing needed):**
- `$HOOKER_EVENT` — hook event name
- `$HOOKER_TRANSCRIPT` — path to transcript JSONL
- `$HOOKER_CWD` — working directory
- `$HOOKER_HELPERS` — path to helpers.sh

## Steps

### 1. Validate hook name
Known hooks: SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure, Notification, SubagentStart, SubagentStop, Stop, TeammateIdle, TaskCompleted, InstructionsLoaded, ConfigChange, WorktreeCreate, WorktreeRemove, PreCompact, PostCompact, Elicitation, ElicitationResult, SessionEnd

If no hook name provided, ask user. Group by category:
- **Session**: SessionStart, SessionEnd, InstructionsLoaded
- **Tools**: PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest
- **Flow**: UserPromptSubmit, Stop, TaskCompleted
- **Agents**: SubagentStart, SubagentStop, TeammateIdle
- **Compact**: PreCompact, PostCompact
- **Config**: ConfigChange, WorktreeCreate, WorktreeRemove
- **MCP**: Elicitation, ElicitationResult
- **Other**: Notification

### 2. Ask what user wants to achieve
Don't ask for "type" directly — ask what they want to happen. Based on the answer, choose the best mode:

- **Static content injection** → Mode 1 (template only)
  - "Dodaj kontekst na starcie sesji" → `SessionStart.md` with `type: inject`
- **Conditional action** → Mode 2 (template + match script)
  - "Przypominaj o docs ale tylko gdy zmieniałem pliki" → `Stop.md` (remind) + `Stop.match.sh`
- **Dynamic content / file reading / complex logic** → Mode 3 (standalone match script)
  - "Wstrzyknij CLAUDE.md do subagentów" → `SubagentStart.match.sh` with `inject "$(cat CLAUDE.md)"`
  - "Blokuj deploy w piątki" → `PreToolUse.match.sh` with date check + `deny`

### 3. Example match scripts with helpers

**Dynamic file injection (e.g. inject CLAUDE.md into subagents):**
```bash
#!/bin/bash
source "${HOOKER_HELPERS}"
CLAUDE_MD=$(cat CLAUDE.md 2>/dev/null || true)
[ -z "$CLAUDE_MD" ] && exit 1
inject "$CLAUDE_MD"
exit 0
```

**Conditional deny with visible + hidden message:**
```bash
#!/bin/bash
source "${HOOKER_HELPERS}"
INPUT=$(cat)
CMD=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"\K[^"]+' || true)
DAY=$(date +%u)
if [ "$DAY" = "5" ] && echo "$CMD" | grep -qi 'deploy\|push'; then
    deny "Piątek — nie robimy deployów. <hidden>Zaproponuj alternatywę na poniedziałek.</hidden>"
    exit 0
fi
exit 1
```

**Remind with dynamic content:**
```bash
#!/bin/bash
source "${HOOKER_HELPERS}"
# Only fire if files were modified
[ -z "$HOOKER_TRANSCRIPT" ] || [ ! -f "$HOOKER_TRANSCRIPT" ] && exit 1
grep -qP '"tool_name"\s*:\s*"(Edit|Write|NotebookEdit)"' "$HOOKER_TRANSCRIPT" || exit 1
remind "Zmieniałeś pliki — sprawdź docs i testy. $(load_md 'checklist.md')"
exit 0
```

**Conditional warn (PostToolUse):**
```bash
#!/bin/bash
source "${HOOKER_HELPERS}"
INPUT=$(cat)
FILE=$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"\K[^"]+' || true)
LINES=$(wc -l < "$FILE" 2>/dev/null || echo 0)
if [ "$LINES" -gt 500 ]; then
    warn "Plik $FILE ma ${LINES} linii — rozważ podział."
    exit 0
fi
exit 1
```

### 4. Create files

1. `mkdir -p .claude/hooker`
2. Depending on mode:
   - Mode 1: Write `.claude/hooker/{HookName}.md` only
   - Mode 2: Write `.claude/hooker/{HookName}.md` + `.claude/hooker/{HookName}.match.sh`
   - Mode 3: Write `.claude/hooker/{HookName}.match.sh` only
3. `chmod +x` any `.match.sh` files

### 5. TEST

**Critical.** After creating, test immediately:

1. Find transcript:
   ```bash
   ls -t ~/.claude/projects/*/transcript.jsonl 2>/dev/null | head -1
   ```

2. Test match script standalone:
   ```bash
   echo '{"hook_event_name": "{HookName}", "transcript_path": "/path/to/transcript.jsonl", "session_id": "test", "cwd": "'$(pwd)'"}' \
     | HOOKER_HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/helpers.sh" \
       HOOKER_EVENT="{HookName}" \
       HOOKER_CWD="$(pwd)" \
       HOOKER_TRANSCRIPT="/path/to/transcript.jsonl" \
       .claude/hooker/{HookName}.match.sh
   echo "Exit code: $?"
   ```

3. Full integration test through inject.sh:
   ```bash
   echo '{"hook_event_name": "{HookName}", "transcript_path": "/path/to/transcript.jsonl", "session_id": "test", "cwd": "'$(pwd)'"}' \
     | CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/inject.sh"
   ```

4. Show test result. Fix and re-test if needed.

### 6. Confirm
Show the user what was created and remind:
- Project-level `.claude/hooker/` overrides plugin defaults in `templates/`
- Files can be edited anytime
- `chmod +x` is required for `.match.sh` files

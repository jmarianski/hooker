---
description: "Hooker main hub — browse recipes, create hooks, show status"
args: "[recipe-name | natural language description | list|install|remove|installed]"
---

# Hooker

Universal hook injection framework for Claude Code. This is the main entry point.

## With natural language description
If the user describes what they want (e.g. `/hooker:recipe block deploys on fridays`, `/hooker:recipe remind about docs`):
1. Figure out which hook event(s) are needed
2. Check if an existing recipe covers this — if so, offer to install it
3. Otherwise, decide the best mode (static template, conditional, or dynamic match script)
4. Create the files in `.claude/hooker/`
5. Test it

## Browse and install pre-built recipes
Mix and match recipes to build your setup.

## Without arguments
1. Scan `${CLAUDE_PLUGIN_ROOT}/recipes/*/recipe.json` — read each `recipe.json`
2. Scan `.claude/hooker/` to detect which recipes are already installed (match filenames against recipe contents)
3. Show a list like:

```
Available recipes:

  [installed] remind-to-update-docs
              Reminds about docs/tests when stopping after file changes
              Hooks: Stop

  [  ready  ] agent-gets-claude-context
              Injects CLAUDE.md + MEMORY.md into subagents
              Hooks: SubagentStart

  [  ready  ] no-friday-deploys
              Blocks deploys and pushes on Fridays
              Hooks: PreToolUse
```

4. Ask user which recipe(s) to install

## With recipe name (e.g. `/hooker:recipe remind-to-update-docs`)
Install that recipe directly:
1. Read `${CLAUDE_PLUGIN_ROOT}/recipes/{name}/recipe.json`
2. Show description and hooks
3. Copy hook files to `.claude/hooker/`
4. `chmod +x` any `.match.sh` files
5. Confirm installation

## Subcommands
- `list` — show all available recipes (same as no args)
- `install <name> [name2...]` — install one or more recipes
- `remove <name>` — remove a recipe's files from `.claude/hooker/`
- `installed` — show only currently installed recipes

## Combining recipes
Multiple recipes can coexist if they target different hooks. If two recipes target the same hook:
1. Warn the user about the conflict
2. Offer to merge (create a combined match script that runs both)
3. Or let user pick one

## Installing a recipe — steps
1. Read `${CLAUDE_PLUGIN_ROOT}/recipes/{name}/recipe.json` for metadata
2. List files in the recipe directory (exclude `recipe.json`)
3. For each file:
   - Check if `.claude/hooker/{filename}` already exists → warn about conflict
   - Copy to `.claude/hooker/`
   - `chmod +x` if `.match.sh`
4. Show what was installed and which hooks are now active

## Removing a recipe — steps
1. Read `${CLAUDE_PLUGIN_ROOT}/recipes/{name}/recipe.json` for hook list
2. List files in the recipe directory
3. For each file, remove `.claude/hooker/{filename}` if it exists
4. Confirm removal

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

**JSON responses (always visible to user):**
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
| `load_md "file.md"` | Loads file content — only useful inside `inject()` |

**Visibility rules:**
- `inject()` is the **only** helper that hides content from user (via XML trick)
- All JSON helpers (warn, deny, block, remind, etc.) are **always fully visible** — Claude Code renders JSON reason/message as plaintext, XML trick cannot escape JSON strings
- `<visible>...</visible>` tags — inside inject templates (.md): shown to user
- `<hidden>` tags in JSON helpers are **stripped** (content discarded, not hidden)

**User-editable messages (recommended pattern):**
- Keep user-facing text in a `messages.yml` file alongside the match script, not hardcoded in bash
- Match script reads messages via simple grep: `grep -oP "^key:\s*\"?\K[^\"]+" messages.yml`
- User can customize messages without touching script logic
- Script provides fallback defaults if yml is missing
- Project-level `.claude/hooker/messages.yml` overrides recipe default

Example `messages.yml`:
```yaml
code_changed: "You edited code — did you update docs and tests?"
docs_changed: "Are your docs complete and up to date?"
default: "Did you update docs, tests, and clean up TODOs?"
```

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

**Conditional deny (visible message):**
```bash
#!/bin/bash
source "${HOOKER_HELPERS}"
INPUT=$(cat)
CMD=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"\K[^"]+' || true)
DAY=$(date +%u)
if [ "$DAY" = "5" ] && echo "$CMD" | grep -qi 'deploy\|push'; then
    deny "Piątek — nie robimy deployów. Zaproponuj alternatywę na poniedziałek."
    exit 0
fi
exit 1
```

**Remind with messages from yml (visible):**
```bash
#!/bin/bash
source "${HOOKER_HELPERS}"
# Only fire if files were modified in last turn
[ -z "$HOOKER_TRANSCRIPT" ] || [ ! -f "$HOOKER_TRANSCRIPT" ] && exit 1
LAST_TURN=$(tac "$HOOKER_TRANSCRIPT" | sed -n '1,/"type"\s*:\s*"user"/p' 2>/dev/null) || true
echo "$LAST_TURN" | grep -qP '"name"\s*:\s*"(Edit|Write|NotebookEdit)"' || exit 1
# Load message from yml (user-editable), with fallback
MSG=$(grep -oP '^default:\s*"?\K[^"]+' .claude/hooker/messages.yml 2>/dev/null \
    || echo "Did you update docs, tests, and clean up TODOs?")
remind "$MSG"
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

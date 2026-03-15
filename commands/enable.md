---
description: "Enable a hook by creating its template and match script"
args: "<HookName> [type]"
---

# Enable a Hooker Hook

Create a template file and optionally a match script for the specified hook.

## Arguments
- `HookName` (required): One of the 21 hook event names
- `type` (optional): Template type — `inject`, `remind`, `block`, `allow`, `deny`, `context`

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
Don't ask for "type" directly — ask what they want to happen. Examples:
- "Chcę przypominajkę o dokumentacji przy stopie" → type: remind + match script checking for Edit/Write
- "Chcę blokować rm -rf" → type: deny + match on PreToolUse
- "Chcę dodać kontekst na starcie sesji" → type: inject, no match script

### 3. Suggest the best `type` for the hook
- Stop → `remind`
- PreToolUse → `allow` or `deny`
- SessionStart, PreCompact, SubagentStart → `inject`
- UserPromptSubmit → `inject` or `block`
- PostToolUse → `context`
- Default → `inject`

### 4. Create match script if needed
If the action should only fire conditionally, write a match script.

**Match script contract:**
- Receives hook input JSON on stdin
- Input JSON always contains: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `permission_mode`
- `transcript_path` points to a JSONL file with the full conversation transcript
- Exit 0 = match (fire the hook action), exit non-0 = skip
- Must be executable (`chmod +x`)

**JSONL transcript format** (each line is a JSON object):
- Tool uses: `{"type": "tool_use", "tool_name": "Edit", "tool_input": {...}}`
- Tool results: `{"type": "tool_result", "tool_name": "Edit", "tool_result": {...}}`
- Messages: `{"type": "message", "role": "user|assistant", "content": "..."}`

**Example match scripts:**

File was modified:
```bash
#!/bin/bash
set -euo pipefail
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | grep -oP '"transcript_path"\s*:\s*"\K[^"]+' || true)
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 1
grep -qP '"tool_name"\s*:\s*"(Edit|Write|NotebookEdit)"' "$TRANSCRIPT"
```

Bash command contained dangerous pattern:
```bash
#!/bin/bash
set -euo pipefail
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | grep -oP '"transcript_path"\s*:\s*"\K[^"]+' || true)
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 1
grep -qP '"command"\s*:\s*"[^"]*rm\s+-rf' "$TRANSCRIPT"
```

Specific file was touched:
```bash
#!/bin/bash
set -euo pipefail
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | grep -oP '"transcript_path"\s*:\s*"\K[^"]+' || true)
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 1
grep -qP '"file_path"\s*:\s*"[^"]*README\.md"' "$TRANSCRIPT"
```

### 5. Create files

1. `mkdir -p .claude/hooker`
2. Write `.claude/hooker/{HookName}.md` with frontmatter and content
3. If match script needed, write `.claude/hooker/{HookName}.match.sh` and `chmod +x`

### 6. TEST the match script

**This is critical.** After creating the match script, test it immediately:

1. Find the current session's transcript path. Run:
   ```bash
   ls -t ~/.claude/projects/*/transcript.jsonl 2>/dev/null | head -1
   ```

2. Create a test input JSON:
   ```bash
   echo '{"hook_event_name": "{HookName}", "transcript_path": "/path/to/transcript.jsonl", "session_id": "test", "cwd": "'$(pwd)'"}' | .claude/hooker/{HookName}.match.sh
   echo "Exit code: $?"
   ```

3. If the script should match (because the condition is true in current session), expect exit 0.
   If it should NOT match, expect exit 1.

4. Show the user the test result and explain. If the script doesn't work as expected, fix it and re-test.

5. Optionally, do a full integration test through inject.sh:
   ```bash
   echo '{"hook_event_name": "{HookName}", "transcript_path": "/path/to/transcript.jsonl", "session_id": "test", "cwd": "'$(pwd)'"}' | CLAUDE_PLUGIN_ROOT=. bash ${CLAUDE_PLUGIN_ROOT}/scripts/inject.sh
   ```

### 7. Confirm
Show the user:
- Created template: `.claude/hooker/{HookName}.md`
- Created match script: `.claude/hooker/{HookName}.match.sh` (if any)
- Remind: project-level overrides plugin defaults
- They can edit these files anytime to tweak behavior

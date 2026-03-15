# Hooker — Roadmap

## v0.1.0 (current) — Foundation

- [x] Universal `inject.sh` handler for all 21 hook events
- [x] Template system: `templates/{HookName}.md` + project overrides `.claude/hooker/`
- [x] 8 action types: `inject`, `remind`, `block`, `allow`, `deny`, `warn`, `ask`, `context`
- [x] Match scripts: `{HookName}.match.sh` — arbitrary conditional logic
- [x] Loop-safe `remind` for Stop hook (`stop_hook_active` check)
- [x] Logging system (`~/.cache/hooker/hooker.log`)
- [x] Skills: `/hooker:config`, `/hooker:status`, `/hooker:enable`
- [x] Default template: Stop + documentation/tests reminder (with match script)

---

## Potential features — worth considering

### Match script improvements

- [ ] **Pass hook-specific fields as env vars** — match scripts currently get raw JSON on stdin which requires grep/jq parsing. Could export `HOOKER_TOOL_NAME`, `HOOKER_FILE_PATH`, `HOOKER_COMMAND` etc. as env vars for simpler matching
- [ ] **Built-in matchers via frontmatter** — for simple cases, allow `match_tool: Edit,Write` or `match_pattern: rm\s+-rf` in YAML frontmatter without needing a separate .match.sh file. Fall back to .match.sh for complex logic
- [ ] **Match script chaining** — multiple `.match.sh` files per hook (AND/OR logic), e.g. `Stop.match.sh` + `Stop.match-docs.sh`
- [ ] **Negate match** — frontmatter `match_negate: true` to invert match result (fire when script does NOT match)

### Conversation analysis

- [ ] **`/hooker:analyze`** — scan current conversation (like hookify) to detect patterns where user corrected Claude, then propose hooks + match scripts. Could also optionally grep transcript JSONL for cross-session patterns
- [ ] **`/hooker:learn`** — when user says "zapamiętaj żeby tego nie robić", auto-create a PreToolUse deny hook with match script

### Guardrails (hookify-like, but with match scripts)

- [ ] **Preset guardrail templates** — ready-made templates for common patterns:
  - `PreToolUse-no-rm-rf.md` + `.match.sh` — block `rm -rf /`
  - `PreToolUse-no-force-push.md` + `.match.sh` — block `git push --force` to main/master
  - `PreToolUse-protect-env.md` + `.match.sh` — block Read/Edit of `.env`, credentials
  - `PreToolUse-no-console-log.md` + `.match.sh` — deny writing console.log
  - `Stop-check-tests.md` + `.match.sh` — remind about tests if code changed
  - `Stop-check-types.md` + `.match.sh` — remind about type checking
- [ ] **`/hooker:guard`** — quick-enable common guardrails interactively

### Context injection presets

- [ ] **SessionStart templates** — inject project context, coding conventions, team agreements on session start
- [ ] **SubagentStart templates** — inject instructions for subagents (e.g. "always use Polish", "follow project conventions")
- [ ] **PreCompact templates** — custom compaction instructions (like kompakt but as part of hooker)

### UX / management

- [ ] **`/hooker:test <HookName>`** — test a hook's match script + template against current transcript without actually firing the hook
- [ ] **`/hooker:disable <HookName>`** — remove/disable a project-level hook override
- [ ] **`/hooker:log`** — show recent log entries, filter by hook name, tail mode
- [ ] **Dry-run mode** — `HOOKER_DRY_RUN=1` logs what would happen without actually injecting/blocking
- [ ] **Hook timing stats** — log execution time per hook, warn if match scripts are slow

### Advanced

- [ ] **Hook composition** — one template references another, e.g. Stop template includes a checklist loaded from separate files
- [ ] **Conditional content** — template content varies based on match script output (match script outputs text, not just exit code)
- [ ] **Node.js / Python match scripts** — not just bash; detect by extension (`.match.js`, `.match.py`)
- [ ] **HTTP match endpoint** — `match_url: http://localhost:3000/check` for integration with external services
- [ ] **Marketplace publishing** — publish to Anthropic/obra marketplace

### Presets (ready-made hook + match script + outer tool bundles)

- [ ] **Ralph Wiggum preset** — faithful implementation of Huntley's autonomous looping technique. NOT a Stop hook loop (that's what the broken official plugin does). Instead: outer bash loop spawning fresh `claude -p` sessions + Hooker hooks for continuity:
  - `SessionStart` (inject) — loads original prompt + progress report from previous iterations
  - `SessionEnd` / `Stop` — saves iteration results to state file (e.g. `.claude/hooker/ralph-state.json`)
  - Generated bash wrapper script with `--max-iterations` and `--completion-promise` flags
  - Each iteration = clean context (the whole point of Ralph), hooks provide memory across iterations
  - See: ghuntley.com/ralph for original concept, official plugin's architectural flaw is using Stop hook to keep single session alive instead of fresh sessions

### Integration with other plugins

- [ ] **Kompakt coexistence** — detect if kompakt is installed, skip PreCompact if kompakt handles it (or offer to replace kompakt's functionality)
- [ ] **Hookify coexistence** — detect hookify, avoid duplicate guardrails, share rule definitions

---

## Non-goals

- Replacing hookify's built-in regex matching engine — match scripts are more powerful and flexible
- Building a full workflow/methodology framework (that's superpowers' domain)
- Caching/persistence between hook invocations — keep it stateless and simple
- Ralph Wiggum via Stop hook blocking — this is architecturally wrong (context rot), use outer loop + session hooks instead

---
description: "Ralph Wiggum — autonomous multi-iteration task execution with fresh context"
args: "[task description | status | stop | help]"
---

# Ralph Wiggum — Skill Assistant

Autonomous iteration loop. Each iteration = fresh context (no rot). State persists via `.claude/ralph-state.json`.

## When invoked

### With task description: `/hooker:ralph build feature X with tests`

1. **Check prerequisites:**
   - Is `ralph-wiggum` recipe installed? Check `.claude/hooker/ralph-wiggum/` or merged hooks
   - If not: install it first (`/hooker:recipe install ralph-wiggum`)

2. **Initialize state:**
   ```bash
   mkdir -p .claude
   echo '{"iteration": 0, "completed": false, "task": "USER_TASK_HERE"}' > .claude/ralph-state.json
   ```

3. **If everything ready — run the loop:**
   ```bash
   MAX_ITER=10
   TIMEOUT=240
   
   for i in $(seq 1 $MAX_ITER); do
     echo "=== Ralph iteration $i ==="
     OUTPUT=$(timeout ${TIMEOUT}s claude -p "RALPH_START iteration=$i. TASK_HERE" 2>&1) || true
     echo "$OUTPUT"
     
     # Check completion
     if echo "$OUTPUT" | grep -q "RALPH_DONE"; then
       echo "Complete after $i iterations"
       break
     fi
     grep -q '"completed": true' .claude/ralph-state.json 2>/dev/null && break
     sleep 2
   done
   ```

4. **Monitor and report** — after loop ends, summarize what was accomplished

### With `status`: `/hooker:ralph status`

Read and display `.claude/ralph-state.json`:
- Current iteration
- Task description  
- Last summary
- Completed status

### With `stop`: `/hooker:ralph stop`

Mark task complete and clean up:
```bash
# Update state to completed
jq '.completed = true' .claude/ralph-state.json > tmp && mv tmp .claude/ralph-state.json
# Or if no jq:
sed -i 's/"completed": false/"completed": true/' .claude/ralph-state.json
```

### With `help`: `/hooker:ralph help`

Explain how Ralph Wiggum works:
- Fresh context per iteration prevents context rot on long tasks
- `SessionStart` hook loads previous iteration summary
- `Stop` hook asks "done?" and saves progress
- Outer loop checks for `RALPH_DONE` marker
- Timeout 4min per iteration fits API TTL

## Decision logic

```
Is ralph-wiggum recipe installed?
├─ NO → Offer to install, then continue
└─ YES
    │
    Is task description provided?
    ├─ NO → Show status or help
    └─ YES
        │
        Is task clear and actionable?
        ├─ NO → Ask clarifying questions
        └─ YES
            │
            Initialize state and RUN THE LOOP
            (use bash with timeout, monitor output)
```

## Key parameters

- `MAX_ITER=10` — safety limit, adjustable
- `TIMEOUT=240` — 4 minutes per iteration (API TTL safe)
- `RALPH_START` — marker that triggers SessionStart hook
- `RALPH_DONE` — marker that signals completion

## State file

`.claude/ralph-state.json`:
```json
{
  "iteration": 3,
  "completed": false,
  "task": "Build feature X",
  "summary": "Core done, need tests",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

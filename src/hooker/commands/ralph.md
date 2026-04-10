---
description: "Ralph Wiggum — autonomous multi-iteration task execution"
args: "[task description]"
---

# Ralph Wiggum

Run long tasks across multiple fresh Claude sessions to prevent context rot.
Each iteration gets fresh context; state persists via `.claude/ralph-state.json`.

## When user provides a task

### 1. Check prerequisites

Ralph-wiggum plugin must be installed (provides SessionStart/Stop hooks for spawned sessions):
```bash
ls ~/.claude/plugins/cache/hooker-marketplace/ralph-wiggum 2>/dev/null && echo "installed" || echo "not installed"
```

If not installed, tell user: `claude plugins add hooker-marketplace/ralph-wiggum`

### 2. Start the loop in background

```bash
mkdir -p .claude
(
  i=1
  while [ $i -le 20 ]; do  # safety limit
    echo "iteration $i started at $(date)" >> .claude/ralph.log
    RALPH_ITERATION=$i RALPH_TASK="TASK_HERE" timeout 300 claude -p "TASK_HERE" >> .claude/ralph-$i.log 2>&1
    
    if grep -q "RALPH_DONE" .claude/ralph-$i.log; then
      echo '{"completed":true,"iteration":'$i',"timestamp":"'$(date -Iseconds)'"}' > .claude/ralph-state.json
      echo "completed at iteration $i" >> .claude/ralph.log
      break
    fi
    i=$((i+1))
    sleep 2
  done
) &
echo $! > .claude/ralph-pid
echo "Ralph started in background. PID: $(cat .claude/ralph-pid)"
```

### 3. Check progress (every ~4 minutes)

```bash
# Is it still running?
if [ -f .claude/ralph-pid ] && kill -0 $(cat .claude/ralph-pid) 2>/dev/null; then
  ITER=$(ls .claude/ralph-*.log 2>/dev/null | wc -l)
  echo "Running. Iteration: $ITER"
  # Last few lines of current iteration
  [ -f ".claude/ralph-$ITER.log" ] && tail -5 ".claude/ralph-$ITER.log"
else
  # Finished - check result
  cat .claude/ralph-state.json 2>/dev/null || echo "No state file"
  echo "=== Final output ==="
  LAST=$(ls .claude/ralph-*.log 2>/dev/null | tail -1)
  [ -n "$LAST" ] && tail -20 "$LAST"
fi
```

### 4. Stop if needed

```bash
[ -f .claude/ralph-pid ] && kill $(cat .claude/ralph-pid) 2>/dev/null
rm -f .claude/ralph-pid
echo "Stopped"
```

### 5. Cleanup

```bash
rm -f .claude/ralph-*.log .claude/ralph-pid .claude/ralph-state.json .claude/ralph.log
```

## Key points

- **Fresh context per iteration** — prevents context rot on long tasks
- **Background execution** — doesn't pollute main conversation
- **4 min timeout per iteration** — safe for API cache TTL
- **RALPH_DONE marker** — spawned session outputs this when task complete
- **Hooks inject context** — SessionStart loads previous summary, Stop saves progress

## Without plugin (manual)

If user doesn't want to install plugin, the pattern still works:
```bash
RALPH_ITERATION=1 claude -p "Task. When done write RALPH_DONE"
# Check output, if not done:
RALPH_ITERATION=2 claude -p "Continue task. Previous: [summary]. When done write RALPH_DONE"
```

The plugin just automates the summary injection.

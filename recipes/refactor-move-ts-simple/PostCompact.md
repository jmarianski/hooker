---
type: inject
---
A PostToolUse hook is active for JS/TS file moves. When you use `mv` on .ts/.tsx/.js/.jsx files, imports are automatically updated via sed. No manual import fixing needed after mv. To skip refactoring (e.g. moving assets), prefix the command: `HOOKER_NO_REFACTOR=1 mv ...`

---
type: inject
---
A PostToolUse hook is active for Python file moves. When you use `mv` on .py files, import statements (from X import Y, import X) are automatically updated via sed. No manual import fixing needed after mv. To skip refactoring (e.g. moving assets), prefix the command: `HOOKER_NO_REFACTOR=1 mv ...`

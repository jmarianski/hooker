---
type: inject
---
A PostToolUse hook is active for Python file moves. When you use `mv` on .py files, import statements are automatically updated via rope (AST-aware) or sed fallback. To skip refactoring (e.g. moving assets), prefix the command: `HOOKER_NO_REFACTOR=1 mv ...`

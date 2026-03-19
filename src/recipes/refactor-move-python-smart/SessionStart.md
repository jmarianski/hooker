---
type: inject
---
A PostToolUse hook is active for Python file moves. When you use `mv` on .py files, import statements are automatically updated. Requires `rope` (pip install rope) for AST-aware rewriting; falls back to sed without it. To skip: `HOOKER_NO_REFACTOR=1 mv ...`

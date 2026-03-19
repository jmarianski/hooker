---
type: inject
---
A PostToolUse hook is active for JS/TS file moves. When you use `mv` on .ts/.tsx/.js/.jsx files, imports and exports are automatically updated. Requires `typescript` (npm global or local) for AST-aware rewriting; falls back to sed without it. To skip refactoring (e.g. moving assets): `HOOKER_NO_REFACTOR=1 mv ...`

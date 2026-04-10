---
type: inject
---
A PostToolUse hook is active for Rust file moves. When you use `mv` on .rs files, mod declarations and use paths are automatically updated via sed. No manual import fixing needed after mv. To skip refactoring, prefix the command: `HOOKER_NO_REFACTOR=1 mv ...`

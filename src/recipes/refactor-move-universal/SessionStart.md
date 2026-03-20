---
type: inject
---
A PostToolUse hook is active for universal path refactoring. When you use `mv`, references to the old path in text files (config, YAML, Dockerfile, scripts, etc.) are automatically updated via sed. To skip: `HOOKER_NO_REFACTOR=1 mv ...`

---
type: inject
---
A PostToolUse hook is active for Go file moves. When you use `mv` on .go files, import paths are automatically updated via sed (reads go.mod for module path). No manual import fixing needed after mv. To skip refactoring (e.g. moving assets), prefix the command: `HOOKER_NO_REFACTOR=1 mv ...`

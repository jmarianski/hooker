---
type: inject
---
A PostToolUse hook is active for Go file moves. When you use `mv` on .go files, import paths are automatically updated via sed (reads go.mod for module path). No manual import fixing needed after mv.

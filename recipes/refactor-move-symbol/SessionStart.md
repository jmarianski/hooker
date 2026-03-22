---
type: inject
---
A PostToolUse hook is active for symbol move detection. When you cut a function/class/export from one file and paste it into another (via two Edit calls), the hook detects the move and suggests import updates. State is tracked between edits — removals are matched with additions automatically.

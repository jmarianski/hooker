---
type: inject
---
A PostToolUse hook is active for PHP file moves. When you use `mv` on .php files, namespace declarations and use statements are automatically updated via phpactor (or sed fallback). Reads composer.json PSR-4 mappings. To skip refactoring (e.g. moving assets), prefix the command: `HOOKER_NO_REFACTOR=1 mv ...`

---
type: inject
---
A PostToolUse hook is active for PHP file moves. When you use `mv` on .php files, namespace and use statements are automatically updated. Requires `phpactor` (composer global) for AST-aware rewriting; falls back to composer.json PSR-4 + sed without it. To skip: `HOOKER_NO_REFACTOR=1 mv ...`

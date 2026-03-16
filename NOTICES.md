# Third-Party Notices

Hooker recipes are inspired by and/or adapted from the following projects and authors.
Where code is adapted (not just conceptually inspired), the original license applies.

## MIT-Licensed Sources (code may be adapted)

### claudekit
- **Author:** Carl Rannaberg
- **URL:** https://github.com/carlrannaberg/claudekit
- **License:** MIT
- **Recipes inspired:** detect-lazy-code, protect-sensitive-files, self-review-on-stop

### claude-format-hook
- **Author:** Ryan Lewis
- **URL:** https://github.com/ryanlewis/claude-format-hook
- **License:** MIT
- **Recipes inspired:** auto-format

### claude-code-hooks (karanb192)
- **Author:** karanb192
- **URL:** https://github.com/karanb192/claude-code-hooks
- **License:** MIT
- **Recipes inspired:** block-dangerous-commands, protect-sensitive-files

### ruff-claude-hook
- **Author:** TMYuan
- **URL:** https://github.com/TMYuan/ruff-claude-hook
- **License:** MIT
- **Recipes inspired:** auto-format (Python/ruff)

### claude-code-showcase
- **Author:** Chris Wiles
- **URL:** https://github.com/ChrisWiles/claude-code-showcase
- **License:** MIT
- **Recipes inspired:** skip-acknowledgments

## Existing Plugins (referenced in README, not bundled)

### safety-net
- **Author:** J Liew (kenryu42)
- **URL:** https://github.com/kenryu42/claude-code-safety-net
- **License:** MIT
- **Note:** Production-grade bash guardrail plugin. Referenced as a more complete alternative to our block-dangerous-commands recipe.

### hookify
- **Author:** Daisy Hollman (Anthropic)
- **URL:** https://github.com/anthropics/claude-code/tree/main/plugins/hookify
- **License:** Anthropic Commercial Terms
- **Note:** Official guardrail/policy engine. Referenced for comparison; no code copied.

### kompakt
- **Author:** Jacek Marianski
- **URL:** https://gitlab.com/treetank/kompakt
- **License:** MIT
- **Note:** Custom summarization plugin by the same author as Hooker.

### claudekit
- **Author:** Carl Rannaberg
- **URL:** https://github.com/carlrannaberg/claudekit
- **License:** MIT
- **Note:** Comprehensive toolkit. Several Hooker recipes adapted from claudekit patterns (with attribution).

### parry
- **Author:** vaporif
- **URL:** https://github.com/vaporif/parry
- **License:** MIT
- **Note:** ML-based prompt injection scanner. Referenced as advanced security tool.

### Dippy
- **Author:** ldayton
- **URL:** https://github.com/ldayton/Dippy
- **License:** MIT
- **Note:** AST-based bash auto-approval. Referenced as advanced permission management tool.

## Conceptual Inspiration (clean-room reimplementation, no code copied)

### Scott Chacon's auto-commit hook
- **Author:** Scott Chacon (GitButler, Git co-creator)
- **URL:** https://gist.github.com/schacon/a3683d51175f0240b900d4c224dbc676
- **Blog:** https://blog.gitbutler.com/automate-your-ai-workflows-with-claude-code-hooks/
- **License:** None specified
- **Recipes inspired:** auto-checkpoint

### claude-code-hooks-mastery
- **Author:** disler
- **URL:** https://github.com/disler/claude-code-hooks-mastery
- **License:** None specified
- **Recipes inspired:** git-context-on-start

### Claude Code Hooks Guide (Anthropic)
- **URL:** https://code.claude.com/docs/en/hooks-guide
- **License:** Anthropic Commercial Terms
- **Note:** Hook event API and patterns are publicly documented; no code copied

### Blog posts and tutorials
- Blake Crosley — https://blakecrosley.com/blog/claude-code-hooks-tutorial
- paddo.dev — https://paddo.dev/blog/claude-code-hooks-guardrails/
- Steve Kinney — https://stevekinney.com/courses/ai-development/claude-code-hook-examples
- claudefa.st — https://claudefa.st/blog/tools/hooks/session-lifecycle-hooks
- John Lindquist — https://gist.github.com/johnlindquist/23fac87f6bc589ddf354582837ec4ecc
- Cameron Westland — https://cameronwestland.com/building-my-first-claude-code-hooks-automating-the-workflow-i-actually-want/

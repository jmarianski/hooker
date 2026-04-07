# Codex Compatibility Analysis

This document compares the current Claude Code oriented design of `hooker` and `cache-catcher`
 with the hook system and plugin model in `../openai-codex`.

Scope:
- ignore `PreCompact` and `PostCompact`
- focus on hooks available in Codex today
- evaluate both direct adaptation and a sidecar `hooker-codex` model

## 1. What Codex supports today

From `../openai-codex/codex-rs/hooks/src/engine/config.rs`, Codex currently parses these hook
events from `hooks.json`:

- `PreToolUse`
- `PostToolUse`
- `SessionStart`
- `UserPromptSubmit`
- `Stop`
- `PreCompact`
- `PostCompact`

For this analysis we ignore `PreCompact` and `PostCompact`.

The useful public set is therefore:

- `PreToolUse`
- `PostToolUse`
- `SessionStart`
- `UserPromptSubmit`
- `Stop`

Important implementation details from `../openai-codex`:

- unknown hook names are ignored during deserialization, not treated as fatal
- only `type: "command"` handlers work today
- `type: "prompt"` and `type: "agent"` are discovered but skipped with warnings
- async hooks are discovered but skipped with warnings
- hook commands run with project `cwd` and JSON payload on `stdin`
- I found no Claude-style plugin env vars such as `CLAUDE_PLUGIN_ROOT` or `CLAUDE_PROJECT_DIR`

## 2. Biggest compatibility gaps

### Event surface

Claude Code oriented `hooker` expects many events that Codex does not currently expose:

- `PermissionRequest`
- `PostToolUseFailure`
- `Notification`
- `SubagentStart`
- `SubagentStop`
- `TeammateIdle`
- `TaskCompleted`
- `ConfigChange`
- `WorktreeCreate`
- `WorktreeRemove`
- `Elicitation`
- `ElicitationResult`
- `SessionEnd`
- `Setup`

That means full Hooker parity is not possible today.

### Path and environment assumptions

Current generated plugins use Claude-specific env vars inside commands and scripts:

- `${CLAUDE_PLUGIN_ROOT}`
- `${CLAUDE_PROJECT_DIR}`

Examples:

- `hooker/hooks/hooks.json`
- `cache-catcher/hooks/hooks.json`

In Codex, these variables do not appear to be injected by the hook runner. So the current commands
would not resolve correctly.

### Tool matcher semantics

Codex `PreToolUse` and `PostToolUse` currently pass `tool_name: "Bash"` in the runtime path I
checked. Matchers for tools other than Bash are therefore not portable as-is.

That matters for recipes conceptually tied to:

- edit/write tools
- subagent hooks
- permission lifecycle hooks

### Output contract differences

Codex understands Claude-like blocking JSON in several places, but the supported surface is smaller:

- `PreToolUse`: supports deny/block behavior
- `PostToolUse`: supports stop/block and additional context
- `SessionStart`: supports additional context and stop
- `UserPromptSubmit`: supports block/stop and additional context
- `Stop`: supports stop/block

This is enough for many recipes, but not enough for the broader Hooker “all hook types” promise.

### Cache telemetry mismatch

`cache-catcher` is built around Claude transcript fields:

- `cache_creation_input_tokens`
- `cache_read_input_tokens`

In Codex I found token usage accounting with:

- `input_tokens`
- `cached_input_tokens`
- `output_tokens`
- `reasoning_output_tokens`
- `total_tokens`

I did not find Claude-style `cache_creation_input_tokens` or `cache_read_input_tokens` in Codex.
So `cache-catcher` cannot be ported 1:1 on transcript parsing alone.

## 3. Hooker recipes vs Codex-supported events

Recipes already fully within the Codex event surface:

- `auto-checkpoint`
- `auto-format`
- `behavior-watchdog`
- `block-dangerous-commands`
- `cache-catcher`
- `cache-watchdog`
- `detect-lazy-code`
- `dir-cleanup`
- `dir-watchdog`
- `git-context-on-start`
- `hook-discovery`
- `no-dismiss-failures`
- `no-force-push-main`
- `protect-sensitive-files`
- `remind-to-update-docs`
- `require-changelog-before-tag`
- `skip-acknowledgments`

Recipes that partially fit only because they also depend on ignored compact hooks:

- `agents-md-context`
- `refactor-move-csharp-smart`
- `refactor-move-go-simple`
- `refactor-move-java-smart`
- `refactor-move-markdown`
- `refactor-move-php-smart`
- `refactor-move-python-simple`
- `refactor-move-python-smart`
- `refactor-move-symbol`
- `refactor-move-ts-simple`
- `refactor-move-ts-smart`
- `refactor-move-universal`
- `reinject-after-compact`

Recipes blocked by missing Codex events:

- `agent-gets-claude-context`
- `scheduled-tasks`
- `session-guardian`

Recipes out of scope because they are compact-only:

- `compact-context`
- `smart-session-notes`

## 4. What this means for Hooker

## Option A: minimal native Codex support inside `hooker`

This is realistic.

What to change:

- generate a Codex-specific `hooks.json` containing only supported events
- stop using `${CLAUDE_PLUGIN_ROOT}` in commands
- switch commands to paths resolvable from Codex plugin layout
- add a Codex runtime mode in `inject.sh`
- replace Claude-specific env assumptions with values derived from:
  - script location
  - hook JSON payload
  - current working directory
- mark recipes with compatibility metadata:
  - `codex: native`
  - `codex: degraded`
  - `codex: unsupported`

What you get:

- a useful subset of Hooker working as a normal Codex plugin
- no false promise of “all Claude hooks”
- a single repo still generating both Claude and Codex artifacts

This is the lowest-risk path.

## Option B: full “Hooker for Codex” compatibility layer

This means trying to preserve the Hooker mental model even where Codex lacks native events.

You would need to emulate missing Claude lifecycle hooks through:

- transcript polling
- wrapper scripts around supported hooks
- state files in `/tmp` or project-local storage
- heuristic inference for “session end”, “tool failure”, “subagent stop”, etc.

This is possible only partially and will be brittle.

Main risks:

- fake events will not line up exactly with Codex execution semantics
- high maintenance cost as Codex internals evolve
- confusing behavior for users because “same recipe name” means different guarantees

I would not recommend this as the primary product direction.

## Option C: separate sidecar plugin `hooker-codex`

This is the cleanest product model.

Shape:

- keep current `hooker` as Claude-first
- create `hooker-codex` next to it
- reuse recipe metadata and helper logic where possible
- ship only Codex-safe hooks and commands
- document degraded/unsupported recipes explicitly

Advantages:

- no need to contort Claude runtime assumptions
- easier plugin manifest/layout for Codex (`.codex-plugin/plugin.json`)
- avoids accidental breakage from mixed Claude/Codex path logic
- clearer user expectation boundary

This is the best long-term option if you want a serious Codex plugin rather than a quick demo.

## 5. What this means for Cache Catcher

`cache-catcher` is not a direct port.

The current design depends on Claude-specific transcript cache telemetry. Codex exposes cache usage
as `cached_input_tokens`, but not the creation-vs-read split that Cache Catcher uses to detect
broken cache behavior.

So there are two viable paths:

### Path 1: Codex-specific redefinition

Build `cache-catcher-codex` as a different diagnostic:

- detect low or zero `cached_input_tokens`
- detect unexpected cache drops after resume
- inspect turn-to-turn token usage deltas instead of Claude transcript ratios

This preserves the product idea, but not the exact detection algorithm.

### Path 2: fold it into Hooker-Codex as a smaller watchdog

Instead of a standalone plugin, implement one Codex recipe or sidecar tool that:

- records `cached_input_tokens`
- warns on persistently cold resumes
- optionally blocks the first prompt after resume if cache looks cold

This is probably the better Codex fit.

Direct 1:1 compatibility with current `cache-catcher` should not be promised.

## 6. Recommended architecture

Recommended order:

1. build a small `hooker-codex` plugin, not a fake full-port of `hooker`
2. support only these events initially:
   - `PreToolUse`
   - `PostToolUse`
   - `SessionStart`
   - `UserPromptSubmit`
   - `Stop`
3. port first the recipes that already naturally fit this set
4. add compatibility metadata to every recipe
5. design a Codex-native replacement for `cache-catcher` instead of forcing transcript parity

First recipe batch worth porting:

- `block-dangerous-commands`
- `no-force-push-main`
- `protect-sensitive-files`
- `require-changelog-before-tag`
- `auto-format`
- `detect-lazy-code`
- `no-dismiss-failures`
- `git-context-on-start`
- `skip-acknowledgments`
- `behavior-watchdog`
- `dir-watchdog`
- `hook-discovery`

Second batch, but explicitly degraded:

- all `refactor-move-*` recipes that can work from `SessionStart` + `PostToolUse`
- `agents-md-context`
- `reinject-after-compact` reimagined as session-start-only reinjection

Do not port yet:

- `session-guardian`
- `agent-gets-claude-context`
- `scheduled-tasks`
- current `cache-catcher` algorithm

## 7. Concrete implementation tasks

Minimal viable `hooker-codex`:

- add Codex plugin manifest under `.codex-plugin/plugin.json`
- generate Codex-only `hooks.json`
- add Codex-aware path resolution in scripts
- remove dependence on `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PROJECT_DIR}`
- add recipe compatibility metadata in `recipe.json`
- generate only Codex-supported recipes into the manifest/hook wiring
- document degraded recipes clearly

For runtime scripts:

- compute plugin root from `dirname "$0"` rather than Claude env vars
- derive project root from `cwd` payload or current working directory
- treat unsupported events as nonexistent, not soft-fallback magic

For `cache-catcher`:

- decide whether it becomes:
  - a separate `cache-catcher-codex`
  - a Hooker recipe
  - or is dropped for Codex until better cache telemetry exists

## 8. Bottom line

`hooker` can absolutely gain useful Codex support.

But:

- it will not be full Claude hook parity
- current generated plugins will not run unchanged in Codex
- `cache-catcher` needs a Codex-native redesign, not a straight port

The strongest model is:

- `hooker` stays Claude-first
- `hooker-codex` sits next to it as a Codex-native sibling
- both share recipe ideas and as much script logic as practical

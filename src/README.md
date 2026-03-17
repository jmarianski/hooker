# src/

Build-time sources for the Hooker plugin. This directory is NOT part of the runtime plugin — see `.pluginignore`.

## commands/

Source templates for skills. Files here are compiled to `commands/` by `build.sh`.

Dynamic sections are marked with `<!-- BUILD:NAME:START -->` / `<!-- BUILD:NAME:END -->` HTML comments. The build script replaces content between markers with generated data.

Skills without a source in `src/commands/` (e.g. config.md, status.md) are static and edited directly in `commands/`.

## build.sh

```bash
bash src/build.sh
```

Generators:
- `RECIPE_CATALOG` — table of all recipes from `recipes/*/recipe.json` + uncovered hooks list

# src/

Build-time sources for the Hooker plugin. This directory is NOT part of the runtime plugin — see `.pluginignore`.

## fragments/

Reusable text fragments that get compiled into skills (`commands/*.md`). Edit fragments here, then update the skills.

Currently manual — run the relevant parts of `commands/*.md` when fragments change. A `build.sh` may be added later if the process becomes unwieldy.

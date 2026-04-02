#!/bin/bash
# Hooker — helper functions for match scripts
# Source this in your match script: source "${HOOKER_HELPERS}"
# Then use: warn "message", deny "reason", allow, block "reason", etc.
#
# Cross-platform: works on Linux, macOS, and Windows (Git Bash).
# No dependencies on python3, perl, or tac.
#
# Visibility:
#   inject() — hidden from user by default (XML trick). Use <visible> tags to show parts.
#   JSON helpers (warn, deny, block, remind, allow, ask) — ALWAYS VISIBLE to user.
#     <hidden> tags are stripped but content is NOT hidden (Claude Code renders
#     JSON reason/message as plaintext — XML trick cannot escape JSON strings).
#   load_md "file.md" — only useful inside inject(), not inside JSON helpers.

# @bundle helpers/json.sh
# @bundle helpers/utils.sh
# @bundle helpers/runtime.sh
# @bundle helpers/responses.sh
# @bundle helpers/injection.sh
# @bundle helpers/files.sh

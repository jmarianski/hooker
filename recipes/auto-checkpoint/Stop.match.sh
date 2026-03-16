#!/bin/bash
# Auto-commit checkpoint on stop
# Inspired by Scott Chacon's approach (clean-room reimplementation)

# Only in git repos
git rev-parse --git-dir &>/dev/null || exit 1

# Only if there are changes
git diff-index --quiet HEAD 2>/dev/null && exit 1

# Stage and commit
git add -A &>/dev/null
git commit -m "checkpoint: hooker auto-save" --no-verify &>/dev/null

exit 1

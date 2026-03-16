#!/bin/bash
# Skip acknowledgments — inject instruction to be direct
# Adapted from ChrisWiles/claude-code-showcase (MIT)
source "${HOOKER_HELPERS}"

inject "Skip acknowledgments and filler phrases like 'Great question!', 'You're absolutely right!', 'That's a great idea!'. Go straight to the answer or action."
exit 0

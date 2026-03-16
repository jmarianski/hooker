#!/bin/bash
# Protect sensitive files from reading/editing
# Adapted from claudekit (MIT) and karanb192/claude-code-hooks (MIT)
source "${HOOKER_HELPERS}"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"\K[^"]+' || true)

# Only check file-accessing tools
case "$TOOL" in
    Read|Edit|Write|NotebookEdit) ;;
    Bash)
        CMD=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"\K[^"]+' || true)
        # Check if bash command accesses sensitive files
        if echo "$CMD" | grep -qP '\.(env|pem|key|p12|pfx|jks)\b|id_rsa|id_ed25519|credentials|\.secrets'; then
            deny "Blocked: bash command accesses sensitive files"
            exit 0
        fi
        exit 1
        ;;
    *) exit 1 ;;
esac

FILE=$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"\K[^"]+' || true)
[ -z "$FILE" ] && exit 1

# Sensitive file patterns
if echo "$FILE" | grep -qP '\.env($|\.)'; then
    deny "Blocked: .env files are protected"
    exit 0
fi

if echo "$FILE" | grep -qP 'id_(rsa|ed25519|ecdsa|dsa)(\.pub)?$'; then
    deny "Blocked: SSH keys are protected"
    exit 0
fi

if echo "$FILE" | grep -qP '\.(pem|key|p12|pfx|jks|keystore)$'; then
    deny "Blocked: certificate/key files are protected"
    exit 0
fi

if echo "$FILE" | grep -qP '(credentials|secrets|tokens)\.(json|yaml|yml|toml|ini|conf)$'; then
    deny "Blocked: credential files are protected"
    exit 0
fi

if echo "$FILE" | grep -qP '\.git/(config|credentials)$'; then
    deny "Blocked: git credential files are protected"
    exit 0
fi

exit 1

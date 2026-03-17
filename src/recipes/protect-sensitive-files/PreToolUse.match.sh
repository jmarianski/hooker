#!/bin/bash
# Protect sensitive files from reading/editing
# Adapted from claudekit (MIT) and karanb192/claude-code-hooks (MIT)
source "${HOOKER_HELPERS}"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Only check file-accessing tools
case "$TOOL" in
    Read|Edit|Write|NotebookEdit) ;;
    Bash)
        CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        # Check if bash command accesses sensitive files
        if echo "$CMD" | grep -q '\.\(env\|pem\|key\|p12\|pfx\|jks\)\|id_rsa\|id_ed25519\|credentials\|\.secrets'; then
            deny "Blocked: bash command accesses sensitive files"
            exit 0
        fi
        exit 1
        ;;
    *) exit 1 ;;
esac

FILE=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$FILE" ] && exit 1

# Sensitive file patterns
if echo "$FILE" | grep -q '\.env$\|\.env\.'; then
    deny "Blocked: .env files are protected"
    exit 0
fi

if echo "$FILE" | grep -q 'id_\(rsa\|ed25519\|ecdsa\|dsa\)\(\.pub\)\{0,1\}$'; then
    deny "Blocked: SSH keys are protected"
    exit 0
fi

if echo "$FILE" | grep -q '\.\(pem\|key\|p12\|pfx\|jks\|keystore\)$'; then
    deny "Blocked: certificate/key files are protected"
    exit 0
fi

if echo "$FILE" | grep -q '\(credentials\|secrets\|tokens\)\.\(json\|yaml\|yml\|toml\|ini\|conf\)$'; then
    deny "Blocked: credential files are protected"
    exit 0
fi

if echo "$FILE" | grep -q '\.git/\(config\|credentials\)$'; then
    deny "Blocked: git credential files are protected"
    exit 0
fi

exit 1

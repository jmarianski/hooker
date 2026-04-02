#!/bin/bash
# Protect sensitive files from reading/editing
# Adapted from claudekit (MIT) and karanb192/claude-code-hooks (MIT)
source "${HOOKER_HELPERS}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSGS_FILE=".claude/hooker/protect-sensitive-files.messages.yml"
[ -f "$MSGS_FILE" ] || MSGS_FILE="${SCRIPT_DIR}/messages.yml"

yml_get() {
    sed -n "s/^${1}:[[:space:]]*\"\{0,1\}\([^\"]*\).*/\1/p" "$MSGS_FILE" 2>/dev/null | head -1 || echo "$2"
}

INPUT=$(cat)
TOOL=$(echo "$INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

# Only check file-accessing tools
case "$TOOL" in
    Read|Edit|Write|NotebookEdit) ;;
    Bash)
        CMD=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        # Check if bash command accesses sensitive files
        if echo "$CMD" | grep -q '\.\(env\|pem\|key\|p12\|pfx\|jks\)\|id_rsa\|id_ed25519\|credentials\|\.secrets'; then
            deny "$(yml_get bash_sensitive 'Blocked: bash command accesses sensitive files')"
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
    deny "$(yml_get env_files 'Blocked: .env files are protected')"
    exit 0
fi

if echo "$FILE" | grep -q 'id_\(rsa\|ed25519\|ecdsa\|dsa\)\(\.pub\)\{0,1\}$'; then
    deny "$(yml_get ssh_keys 'Blocked: SSH keys are protected')"
    exit 0
fi

if echo "$FILE" | grep -q '\.\(pem\|key\|p12\|pfx\|jks\|keystore\)$'; then
    deny "$(yml_get cert_files 'Blocked: certificate/key files are protected')"
    exit 0
fi

if echo "$FILE" | grep -q '\(credentials\|secrets\|tokens\)\.\(json\|yaml\|yml\|toml\|ini\|conf\)$'; then
    deny "$(yml_get credential_files 'Blocked: credential files are protected')"
    exit 0
fi

if echo "$FILE" | grep -q '\.git/\(config\|credentials\)$'; then
    deny "$(yml_get git_credentials 'Blocked: git credential files are protected')"
    exit 0
fi

exit 1

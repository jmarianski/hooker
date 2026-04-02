"""Hooker helpers for Python match scripts.

Usage:
    from hooker_helpers import read_input, inject, warn, deny, skip

Environment (set by inject.sh):
    HOOKER_EVENT      — hook event name (PostToolUse, PreToolUse, etc.)
    HOOKER_CWD        — project working directory
    HOOKER_TRANSCRIPT — path to conversation transcript

Contract:
    - Read JSON from stdin (use read_input())
    - Print response JSON to stdout
    - Exit 0 = matched, 1 = no match (skip), 2+ = error
"""
import json
import sys
import os


# --- Input ---

def read_input():
    """Read and parse JSON input from stdin."""
    return json.loads(sys.stdin.read())


def json_field(data, field):
    """Extract a field from hook input (checks top-level and tool_input)."""
    if field in data:
        return data[field]
    if "tool_input" in data and field in data["tool_input"]:
        return data["tool_input"][field]
    return None


# --- Response helpers ---

def inject(text):
    """Hidden context injection (only Claude sees, user doesn't)."""
    print(f"</local-command-stdout>\n\n{text}\n\n<local-command-stdout>")


def visible(text):
    """Visible output (user sees in terminal)."""
    print(text)


def warn(message):
    """System message warning (visible to user and Claude)."""
    event = os.environ.get("HOOKER_EVENT", "PostToolUse")
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": event,
            "systemMessage": message,
        }
    }, ensure_ascii=False))


def deny(reason="Denied by Hooker"):
    """Deny a PreToolUse action."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }, ensure_ascii=False))


def allow(reason="Allowed by Hooker"):
    """Allow a PreToolUse action."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": reason,
        }
    }, ensure_ascii=False))


def ask(reason="Hooker requests confirmation"):
    """Escalate to user for manual decision (PreToolUse only)."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": reason,
        }
    }, ensure_ascii=False))


def block(reason="Blocked by Hooker"):
    """Block with reason (Stop hooks)."""
    print(json.dumps({
        "decision": "block",
        "reason": reason,
    }, ensure_ascii=False))


def remind(message):
    """Block stop with reminder (alias for block)."""
    block(message)


def context(text):
    """Additional context injection (JSON additionalContext field)."""
    print(json.dumps({"additionalContext": text}, ensure_ascii=False))


# --- Transcript helpers ---

def last_turn(transcript_path=None):
    """Get last assistant turn from transcript (filters noise)."""
    path = transcript_path or os.environ.get("HOOKER_TRANSCRIPT", "")
    if not path or not os.path.exists(path):
        return ""
    with open(path) as f:
        all_lines = f.readlines()
    result = []
    for line in reversed(all_lines):
        if '"type":"progress"' in line or '"type":"hook_progress"' in line:
            continue
        if '"type":"user"' in line and "sourceToolAssistantUUID" not in line:
            break
        result.append(line)
    result.reverse()
    return "".join(result)


# --- Flow control ---

def skip():
    """Exit with no-match (silent skip). Use instead of sys.exit(1)."""
    sys.exit(1)


def match():
    """Exit with match (when output was already printed). Use instead of sys.exit(0)."""
    sys.exit(0)


def error(msg=""):
    """Exit with error (inject.sh warns agent). Use instead of sys.exit(2)."""
    if msg:
        print(msg, file=sys.stderr)
    sys.exit(2)

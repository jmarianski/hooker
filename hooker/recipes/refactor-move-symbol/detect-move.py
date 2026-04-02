#!/usr/bin/env python3
"""Hooker: refactor-move-symbol — detect symbol moves between files.

Reads PostToolUse Edit hook input from stdin (JSON).
Tracks removals in a state file. When a matching addition is found,
outputs JSON with move details.

State file: /tmp/hooker_symbol_moves_{session_id}.json
Entries expire after 60 seconds (to avoid false positives across unrelated edits).

Usage: echo '{"tool_input": {...}, ...}' | python3 detect-move.py
Output: {"action": "move_detected", "symbol": "...", "from": "...", "to": "...", "references": N}
     or {"action": "removal_tracked", "symbol": "...", "file": "..."}
     or {"action": "none"}
"""
import sys
import json
import os
import re
import time
import hashlib

# --- Config ---
STATE_DIR = "/tmp"
EXPIRY_SECONDS = 120  # removals older than this are ignored

# --- Symbol extraction ---
# Patterns that identify exported/public symbols across languages
SYMBOL_PATTERNS = [
    # JS/TS: export function/const/class/interface/type/enum
    r'export\s+(?:default\s+)?(?:async\s+)?(?:function|const|let|var|class|interface|type|enum)\s+(\w+)',
    # JS/TS: export { name }
    r'export\s*\{\s*(\w+)',
    # Python: def/class at module level (no indentation)
    r'^(?:def|class)\s+(\w+)',
    # Java/C#: public/protected class/interface/enum
    r'(?:public|protected)\s+(?:static\s+)?(?:abstract\s+)?(?:class|interface|enum|record)\s+(\w+)',
    # Go: exported function/type (capitalized, at package level)
    r'^func\s+(\w*[A-Z]\w*)',
    r'^type\s+(\w*[A-Z]\w*)',
    # PHP: function/class
    r'(?:public|protected|private)?\s*(?:static\s+)?function\s+(\w+)',
    r'class\s+(\w+)',
]

def extract_symbols(code):
    """Extract symbol names from a code block."""
    symbols = set()
    for pattern in SYMBOL_PATTERNS:
        for match in re.finditer(pattern, code, re.MULTILINE):
            name = match.group(1)
            if name and len(name) > 1 and name not in ('if', 'for', 'while', 'return', 'import', 'from'):
                symbols.add(name)
    return symbols

def normalize_code(code):
    """Normalize code for fuzzy matching — strip whitespace, comments."""
    # Remove single-line comments
    code = re.sub(r'//.*$', '', code, flags=re.MULTILINE)
    code = re.sub(r'#.*$', '', code, flags=re.MULTILINE)
    # Collapse whitespace
    code = re.sub(r'\s+', ' ', code).strip()
    return code

def code_hash(code):
    """Hash normalized code for matching."""
    return hashlib.md5(normalize_code(code).encode()).hexdigest()

# --- State management ---
def state_path(session_id):
    return os.path.join(STATE_DIR, f"hooker_symbol_moves_{session_id}.json")

def load_state(session_id):
    path = state_path(session_id)
    if os.path.exists(path):
        try:
            with open(path) as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            return {"removals": []}
    return {"removals": []}

def save_state(session_id, state):
    path = state_path(session_id)
    with open(path, 'w') as f:
        json.dump(state, f)

def clean_expired(state):
    """Remove entries older than EXPIRY_SECONDS."""
    now = time.time()
    state["removals"] = [
        r for r in state["removals"]
        if now - r.get("timestamp", 0) < EXPIRY_SECONDS
    ]

# --- Reference counting ---
def count_references(symbol, file_path, search_dir="."):
    """Count files that reference the symbol (crude grep)."""
    count = 0
    try:
        for root, dirs, files in os.walk(search_dir):
            # Skip common non-source dirs
            dirs[:] = [d for d in dirs if d not in (
                '.git', 'node_modules', '__pycache__', 'vendor',
                'dist', 'build', 'target', 'bin', 'obj', '.next'
            )]
            for fname in files:
                fpath = os.path.join(root, fname)
                if fpath == file_path:
                    continue
                # Only text-like source files
                if not any(fname.endswith(ext) for ext in (
                    '.ts', '.tsx', '.js', '.jsx', '.py', '.java', '.cs',
                    '.go', '.php', '.rb', '.rs', '.swift', '.kt'
                )):
                    continue
                try:
                    with open(fpath, 'r', errors='ignore') as f:
                        if symbol in f.read():
                            count += 1
                except (IOError, OSError):
                    pass
    except Exception:
        pass
    return count

# --- Main ---
def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        print(json.dumps({"action": "none", "error": "invalid JSON input"}))
        return

    tool_input = input_data.get("tool_input", {})
    if isinstance(tool_input, str):
        try:
            tool_input = json.loads(tool_input)
        except json.JSONDecodeError:
            print(json.dumps({"action": "none"}))
            return

    file_path = tool_input.get("file_path", "")
    old_string = tool_input.get("old_string", "")
    new_string = tool_input.get("new_string", "")
    session_id = input_data.get("session_id", "default")

    if not file_path or (not old_string and not new_string):
        print(json.dumps({"action": "none"}))
        return

    state = load_state(session_id)
    clean_expired(state)

    # Case 1: Something was removed (old_string has content, new_string is empty or much smaller)
    old_symbols = extract_symbols(old_string)
    new_symbols = extract_symbols(new_string)
    removed_symbols = old_symbols - new_symbols

    if removed_symbols and len(old_string) > len(new_string) + 20:
        # Track removal
        removal = {
            "file": file_path,
            "symbols": list(removed_symbols),
            "code_hash": code_hash(old_string),
            "code_preview": old_string[:200],
            "timestamp": time.time(),
        }
        state["removals"].append(removal)
        save_state(session_id, state)

        symbol_list = ", ".join(sorted(removed_symbols))
        print(json.dumps({
            "action": "removal_tracked",
            "symbols": list(removed_symbols),
            "file": file_path,
        }))
        return

    # Case 2: Something was added — check if it matches a tracked removal
    added_symbols = new_symbols - old_symbols

    if added_symbols and len(new_string) > len(old_string) + 20:
        new_hash = code_hash(new_string)

        for removal in state["removals"]:
            # Match by symbol name overlap
            removed_set = set(removal["symbols"])
            matched = added_symbols & removed_set

            if matched and removal["file"] != file_path:
                # Additional check: code similarity (hash or symbol count)
                # Even partial match is interesting
                symbol = sorted(matched)[0]  # primary symbol
                ref_count = count_references(symbol, file_path)

                # Remove matched removal from state
                state["removals"] = [r for r in state["removals"] if r is not removal]
                save_state(session_id, state)

                print(json.dumps({
                    "action": "move_detected",
                    "symbol": symbol,
                    "all_symbols": list(matched),
                    "from": removal["file"],
                    "to": file_path,
                    "references": ref_count,
                }))
                return

    save_state(session_id, state)
    print(json.dumps({"action": "none"}))

if __name__ == "__main__":
    main()

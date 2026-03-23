#!/usr/bin/env python3
"""Hooker: dir-watchdog — scan directories for file bloat.

Reads config from .claude/hooker/dir-watchdog.yml (or defaults).
Outputs JSON array of actions to take.

Usage: python3 scan-dirs.py [config_path]
Output: [{"action": "warn|cleanup", "path": "...", "count": N, "max": N, "ext": "...", "files_to_remove": [...]}]
"""
import os
import sys
import json
import re
from collections import defaultdict

# --- Simple YAML parser (no pyyaml dependency) ---
def parse_simple_yaml(text):
    """Parse a subset of YAML: scalars, lists, and one level of nested objects."""
    result = {}
    current_list = None
    current_list_key = None
    in_rules = False
    current_rule = None
    rules = []

    for line in text.split('\n'):
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue

        # Top-level key: value
        if not line.startswith(' ') and not line.startswith('\t'):
            if current_rule is not None:
                rules.append(current_rule)
                current_rule = None
            current_list = None
            current_list_key = None

            if ':' in stripped:
                key, _, val = stripped.partition(':')
                key = key.strip()
                val = val.strip()
                if key == 'rules':
                    in_rules = True
                    continue
                if val:
                    # Parse value
                    if val.startswith('[') and val.endswith(']'):
                        result[key] = [x.strip().strip('"\'') for x in val[1:-1].split(',')]
                    elif val.isdigit():
                        result[key] = int(val)
                    elif val in ('true', 'false'):
                        result[key] = val == 'true'
                    else:
                        result[key] = val.strip('"\'')
                else:
                    result[key] = None
            continue

        # Inside rules list
        if in_rules:
            if stripped.startswith('- '):
                if current_rule is not None:
                    rules.append(current_rule)
                current_rule = {}
                # Parse "- key: val" on same line
                rest = stripped[2:].strip()
                if ':' in rest:
                    k, _, v = rest.partition(':')
                    k = k.strip()
                    v = v.strip().strip('"\'')
                    if v.isdigit():
                        v = int(v)
                    current_rule[k] = v
            elif current_rule is not None and ':' in stripped:
                k, _, v = stripped.partition(':')
                k = k.strip()
                v = v.strip()
                if v.startswith('[') and v.endswith(']'):
                    current_rule[k] = [x.strip().strip('"\'') for x in v[1:-1].split(',') if x.strip()]
                elif v.isdigit():
                    current_rule[k] = int(v)
                elif v in ('true', 'false'):
                    current_rule[k] = v == 'true'
                else:
                    current_rule[k] = v.strip('"\'')

    if current_rule is not None:
        rules.append(current_rule)

    if rules:
        result['rules'] = rules

    return result

# --- Directory scanning ---
def scan_directory(path, extensions=None, max_files=30):
    """Count files in directory, optionally filtered by extension."""
    if not os.path.isdir(path):
        return []

    files = []
    try:
        for entry in os.listdir(path):
            fpath = os.path.join(path, entry)
            if not os.path.isfile(fpath):
                continue
            if extensions:
                ext = entry.rsplit('.', 1)[-1].lower() if '.' in entry else ''
                if ext not in extensions:
                    continue
            try:
                mtime = os.path.getmtime(fpath)
            except OSError:
                mtime = 0
            files.append((fpath, mtime))
    except OSError:
        return []

    return files

def find_bloated_dirs(root='.', threshold=30):
    """Find directories with too many files of the same extension."""
    results = []
    try:
        for dirpath, dirnames, filenames in os.walk(root):
            # Skip hidden and generated dirs
            dirnames[:] = [d for d in dirnames if d not in (
                '.git', 'node_modules', '__pycache__', 'vendor',
                'dist', 'build', 'target', 'bin', 'obj', '.next', '.claude'
            ) and not d.startswith('.')]

            if not filenames:
                continue

            # Group by extension
            by_ext = defaultdict(list)
            for fname in filenames:
                ext = fname.rsplit('.', 1)[-1].lower() if '.' in fname else 'no_ext'
                by_ext[ext].append(fname)

            for ext, files in by_ext.items():
                if len(files) > threshold:
                    results.append({
                        'path': dirpath,
                        'ext': ext,
                        'count': len(files),
                        'threshold': threshold,
                    })
    except OSError:
        pass
    return results

# --- Main ---
def main():
    config_path = sys.argv[1] if len(sys.argv) > 1 else '.claude/hooker/dir-watchdog.yml'

    # Load config
    config = {}
    if os.path.exists(config_path):
        try:
            with open(config_path) as f:
                config = parse_simple_yaml(f.read())
        except (IOError, OSError):
            pass

    default_threshold = config.get('default_threshold', 30)
    rules = config.get('rules', [])
    actions = []

    # Process configured rules
    for rule in rules:
        path = rule.get('path', '').rstrip('/')
        max_files = rule.get('max_files', default_threshold)
        extensions = rule.get('extensions')
        action = rule.get('action', 'warn')

        if not path:
            continue

        if extensions:
            ext_set = set(e.lower().lstrip('.') for e in extensions)
        else:
            ext_set = None

        files = scan_directory(path, ext_set, max_files)

        if len(files) > max_files:
            # Sort by mtime (oldest first)
            files.sort(key=lambda x: x[1])
            excess = len(files) - max_files
            to_remove = [f[0] for f in files[:excess]]

            ext_label = ','.join(sorted(ext_set)) if ext_set else '*'
            entry = {
                'action': action,
                'path': path,
                'count': len(files),
                'max': max_files,
                'ext': ext_label,
                'excess': excess,
            }

            if action == 'cleanup':
                entry['files_to_remove'] = to_remove
                # Actually remove them
                removed = 0
                for fpath in to_remove:
                    try:
                        os.remove(fpath)
                        removed += 1
                    except OSError:
                        pass
                entry['removed'] = removed
                entry['kept'] = len(files) - removed

            actions.append(entry)

    # Scan unconfigured directories for bloat
    if default_threshold > 0:
        configured_paths = set(r.get('path', '').rstrip('/') for r in rules)
        bloated = find_bloated_dirs('.', default_threshold)
        for b in bloated:
            rel_path = os.path.relpath(b['path'], '.')
            if rel_path in configured_paths:
                continue
            actions.append({
                'action': 'warn_unconfigured',
                'path': rel_path,
                'count': b['count'],
                'max': default_threshold,
                'ext': b['ext'],
            })

    print(json.dumps(actions))

if __name__ == '__main__':
    main()

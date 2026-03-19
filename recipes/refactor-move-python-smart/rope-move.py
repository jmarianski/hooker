#!/usr/bin/env python3
"""Hooker: refactor-move-python-smart — rope-based import rewriting.
Usage: python3 rope-move.py <project_root> <old_path> <new_path>
Outputs JSON: { "count": N, "files": ["path1", "path2"] }
Requires: rope (pip install rope)
"""
import sys
import os
import json

try:
    from rope.base.project import Project
    from rope.refactor.move import MoveModule
except ImportError:
    print(json.dumps({"error": "rope not installed"}))
    sys.exit(1)

if len(sys.argv) < 4:
    print(json.dumps({"error": "Usage: rope-move.py <project_root> <old_path> <new_path>"}))
    sys.exit(1)

project_root = sys.argv[1]
old_path = sys.argv[2]
new_path = sys.argv[3]

try:
    project = Project(project_root)

    # rope needs the file at its OLD location to analyze it.
    # Since the file is already moved, copy it back temporarily.
    old_abs = os.path.join(project_root, old_path)
    new_abs = os.path.join(project_root, new_path)

    # Create old directory if needed
    old_dir = os.path.dirname(old_abs)
    os.makedirs(old_dir, exist_ok=True)

    # Copy new back to old temporarily
    import shutil
    shutil.copy2(new_abs, old_abs)

    try:
        resource = project.get_resource(old_path)

        # Determine destination package
        new_dir = os.path.dirname(new_path)
        dest_pkg = new_dir.replace(os.sep, '.')
        if not dest_pkg:
            dest_pkg = ''

        mover = MoveModule(project, resource)
        changes = mover.get_changes(dest_pkg)

        # Get list of affected files before applying
        changed_files = []
        for change in changes.changes:
            rel = os.path.relpath(change.resource.real_path, project_root)
            if rel not in changed_files:
                changed_files.append(rel)

        project.do(changes)

        # Remove old file if it still exists (rope may have moved it)
        if os.path.exists(old_abs) and os.path.exists(new_abs):
            os.remove(old_abs)

        # Validate the file ended up at new_path
        result = {"count": len(changed_files), "files": changed_files}
        if not os.path.exists(new_abs):
            result["warning"] = f"Expected file at {new_path} but it does not exist. Rope may have moved it elsewhere."
        print(json.dumps(result))
    finally:
        # Clean up: remove temporary old file if still there
        if os.path.exists(old_abs) and old_abs != new_abs:
            try:
                os.remove(old_abs)
            except OSError:
                pass
        project.close()

except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)

#!/usr/bin/env node
// Hooker: refactor-move-ts-smart — AST-aware import rewriting via ts-morph
// Usage: node update-imports.mjs <oldPath> <newPath>
// Assumes file is already at newPath. Updates all imports/exports project-wide.
// Outputs JSON: { "count": N, "files": ["path1", "path2"] }

import { Project } from "ts-morph";
import * as path from "path";

const [oldPath, newPath] = process.argv.slice(2);
if (!oldPath || !newPath) {
  console.error(JSON.stringify({ error: "Usage: node update-imports.mjs <oldPath> <newPath>" }));
  process.exit(1);
}

const oldAbsolute = path.resolve(oldPath);
const newAbsolute = path.resolve(newPath);
const oldNoExt = oldAbsolute.replace(/\.(ts|tsx|js|jsx)$/, "");
const newNoExt = newAbsolute.replace(/\.(ts|tsx|js|jsx)$/, "");

// Try to load tsconfig, fall back to manual file discovery
let project;
try {
  project = new Project({ tsConfigFilePath: "tsconfig.json" });
} catch {
  // No tsconfig — add files manually
  project = new Project();
  project.addSourceFilesAtPaths([
    "**/*.{ts,tsx,js,jsx}",
    "!node_modules/**",
    "!dist/**",
    "!build/**",
    "!.next/**",
  ]);
}

const modifiedFiles = [];

for (const sourceFile of project.getSourceFiles()) {
  const sourceDir = sourceFile.getDirectoryPath();
  let modified = false;

  const declarations = [
    ...sourceFile.getImportDeclarations(),
    ...sourceFile.getExportDeclarations(),
  ];

  for (const decl of declarations) {
    const specValue = decl.getModuleSpecifierValue?.();
    if (!specValue) continue;

    // Skip bare specifiers (node_modules, aliases handled below)
    if (!specValue.startsWith(".")) continue;

    // Resolve what the old specifier pointed to
    const resolved = path.resolve(sourceDir, specValue);
    const resolvedNoExt = resolved.replace(/\.(ts|tsx|js|jsx)$/, "");

    // Match against old path (with or without extension, including /index)
    const isMatch =
      resolvedNoExt === oldNoExt ||
      resolved === oldNoExt ||
      resolvedNoExt === oldNoExt + "/index" ||
      resolved === oldAbsolute;

    if (isMatch) {
      // Compute new relative specifier
      let newRel = path.relative(sourceDir, newNoExt);
      if (!newRel.startsWith(".")) newRel = "./" + newRel;
      // Normalize backslashes (Windows)
      newRel = newRel.replace(/\\/g, "/");

      decl.setModuleSpecifier(newRel);
      modified = true;
    }
  }

  if (modified) {
    sourceFile.saveSync();
    modifiedFiles.push(path.relative(process.cwd(), sourceFile.getFilePath()));
  }
}

console.log(JSON.stringify({ count: modifiedFiles.length, files: modifiedFiles }));

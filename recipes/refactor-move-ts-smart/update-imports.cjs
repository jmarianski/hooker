#!/usr/bin/env node
// Hooker: refactor-move-ts-smart — TypeScript Language Service API
// Same mechanism as VS Code's "Update imports on file move"
// Usage: node update-imports.cjs <oldPath> <newPath>
// Outputs JSON: { "count": N, "files": ["path1", "path2"] }
// Requires: typescript (globally or locally installed)

const ts = require("typescript");
const path = require("path");
const fs = require("fs");

const [oldPath, newPath] = process.argv.slice(2);
if (!oldPath || !newPath) {
  console.error(JSON.stringify({ error: "Usage: node update-imports.cjs <oldPath> <newPath>" }));
  process.exit(1);
}

const oldAbsolute = path.resolve(oldPath);
const newAbsolute = path.resolve(newPath);

// Find tsconfig.json — walk up from file location, then cwd
function findTsConfig(startDir) {
  let dir = startDir;
  while (dir !== path.dirname(dir)) {
    const candidate = path.join(dir, "tsconfig.json");
    if (fs.existsSync(candidate)) return candidate;
    dir = path.dirname(dir);
  }
  return null;
}

const tsConfigPath = findTsConfig(path.dirname(newAbsolute)) || findTsConfig(process.cwd());
if (!tsConfigPath) {
  console.error(JSON.stringify({ error: "No tsconfig.json found" }));
  process.exit(1);
}

// Parse tsconfig
const configFile = ts.readConfigFile(tsConfigPath, ts.sys.readFile);
const parsedConfig = ts.parseJsonConfigFileContent(
  configFile.config,
  ts.sys,
  path.dirname(tsConfigPath)
);

// Create Language Service host
const files = {};
for (const fileName of parsedConfig.fileNames) {
  files[fileName] = { version: 0 };
}

const serviceHost = {
  getScriptFileNames: () => parsedConfig.fileNames,
  getScriptVersion: (fileName) => files[fileName]?.version?.toString() || "0",
  getScriptSnapshot: (fileName) => {
    if (!fs.existsSync(fileName)) return undefined;
    return ts.ScriptSnapshot.fromString(fs.readFileSync(fileName, "utf8"));
  },
  getCurrentDirectory: () => process.cwd(),
  getCompilationSettings: () => parsedConfig.options,
  getDefaultLibFileName: (options) => ts.getDefaultLibFilePath(options),
  fileExists: ts.sys.fileExists,
  readFile: ts.sys.readFile,
  readDirectory: ts.sys.readDirectory,
  directoryExists: ts.sys.directoryExists,
  getDirectories: ts.sys.getDirectories,
};

// Create Language Service
const service = ts.createLanguageService(serviceHost, ts.createDocumentRegistry());

// Get edits for file rename — same API as VS Code
const edits = service.getEditsForFileRename(
  oldAbsolute,
  newAbsolute,
  ts.getDefaultFormatCodeSettings(),
  { quotePreference: "auto" }
);

if (!edits || edits.length === 0) {
  console.log(JSON.stringify({ count: 0, files: [] }));
  process.exit(0);
}

// Apply edits in reverse order (to preserve offsets)
const modifiedFiles = [];
for (const fileEdit of edits) {
  const filePath = fileEdit.fileName;
  if (!fs.existsSync(filePath)) continue;

  let content = fs.readFileSync(filePath, "utf8");

  const changes = [...fileEdit.textChanges].sort((a, b) => b.span.start - a.span.start);
  for (const change of changes) {
    content =
      content.substring(0, change.span.start) +
      change.newText +
      content.substring(change.span.start + change.span.length);
  }

  fs.writeFileSync(filePath, content, "utf8");
  modifiedFiles.push(path.relative(process.cwd(), filePath));
}

console.log(JSON.stringify({ count: modifiedFiles.length, files: modifiedFiles }));

package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"hooker-build/generators"

	"github.com/nikolalohinski/gonja/v2"
	"github.com/nikolalohinski/gonja/v2/exec"
)

func main() {
	pluginFlag := flag.String("plugin", "all", "Plugin to build: hooker, cache-catcher, all")
	flag.Parse()

	srcDir, _ := os.Getwd()
	if _, err := os.Stat(filepath.Join(srcDir, "build.go")); err != nil {
		srcDir, _ = filepath.Abs(filepath.Dir(os.Args[0]))
	}

	repoRoot := filepath.Join(srcDir, "..")

	switch *pluginFlag {
	case "hooker":
		buildHooker(srcDir, repoRoot)
	case "cache-catcher":
		buildCacheCatcher(srcDir, repoRoot)
	case "all":
		buildHooker(srcDir, repoRoot)
		buildCacheCatcher(srcDir, repoRoot)
		buildMarketplace(srcDir, repoRoot)
	default:
		fmt.Fprintf(os.Stderr, "Unknown plugin: %s. Use hooker, cache-catcher, or all.\n", *pluginFlag)
		os.Exit(1)
	}

	fmt.Println("Done.")
}

// =============================================================================
// HOOKER BUILD
// =============================================================================

func buildHooker(srcDir, repoRoot string) {
	hookerSrc := filepath.Join(srcDir, "hooker")
	hookerOut := filepath.Join(repoRoot, "hooker")

	recipes := generators.LoadRecipes(hookerSrc)
	pluginVersion := readVersion(hookerSrc)

	ctx := exec.NewContext(map[string]any{
		"recipes":        recipes,
		"categories":     generators.GroupByCategory(recipes),
		"uncoveredHooks": generators.UncoveredHooks(recipes),
		"coveredHooks":   generators.CoveredHooks(recipes),
		"allHooks":       generators.AllHooks(),
	})

	fmt.Println("Building Hooker plugin...")

	// 1. Commands — gonja templates
	buildCommands(hookerSrc, hookerOut, ctx)

	// 2. Scripts — shell bundling (@bundle directives)
	buildScripts(hookerSrc, hookerOut)

	// 3. Recipes — copy as-is + compile execute.sh
	copyDir(filepath.Join(hookerSrc, "recipes"), filepath.Join(hookerOut, "recipes"), "recipes")
	compileExecutables(hookerSrc, hookerOut, pluginVersion)
	copyDir(filepath.Join(hookerSrc, "hooks"), filepath.Join(hookerOut, "hooks"), "hooks")
	copyDir(filepath.Join(hookerSrc, "templates"), filepath.Join(hookerOut, "templates"), "templates")

	// 3b. Multi-language helpers (Python, JS) — for non-shell match scripts
	copyDir(filepath.Join(hookerSrc, "helpers"), filepath.Join(hookerOut, "helpers"), "helpers")

	// 4. Plugin manifest
	copyFile(filepath.Join(hookerSrc, "plugin.json"), filepath.Join(hookerOut, ".claude-plugin", "plugin.json"), "plugin.json")

	// 5. .pluginignore
	copyFile(filepath.Join(hookerSrc, ".pluginignore"), filepath.Join(hookerOut, ".pluginignore"), ".pluginignore")

	// 6. README.md — gonja template
	buildFile(filepath.Join(hookerSrc, "README.md"), filepath.Join(hookerOut, "README.md"), "README.md", ctx)
}

// =============================================================================
// CACHE-CATCHER BUILD
// =============================================================================

func buildCacheCatcher(srcDir, repoRoot string) {
	ccSrc := filepath.Join(srcDir, "cache-catcher")
	ccOut := filepath.Join(repoRoot, "cache-catcher")

	if _, err := os.Stat(ccSrc); os.IsNotExist(err) {
		fmt.Println("Skipping cache-catcher (no source directory)")
		return
	}

	fmt.Println("Building Cache Catcher plugin...")

	// 1. hooks.json
	copyDir(filepath.Join(ccSrc, "hooks"), filepath.Join(ccOut, "hooks"), "hooks")

	// 2. Scripts (CLI)
	srcScripts := filepath.Join(ccSrc, "scripts")
	outScripts := filepath.Join(ccOut, "scripts")
	if _, err := os.Stat(srcScripts); err == nil {
		os.MkdirAll(outScripts, 0755)
		entries, _ := os.ReadDir(srcScripts)
		for _, e := range entries {
			if e.IsDir() {
				continue
			}
			src := filepath.Join(srcScripts, e.Name())
			dst := filepath.Join(outScripts, e.Name())
			data, _ := os.ReadFile(src)
			writeFile(dst, data)
			os.Chmod(dst, 0755)
			fmt.Printf("  scripts/%s: copied\n", e.Name())
		}
	}

	// 3. match.sh — copy as-is (self-contained, no hooker dependency)
	copyFile(filepath.Join(ccSrc, "match.sh"), filepath.Join(ccOut, "match.sh"), "match.sh")
	os.Chmod(filepath.Join(ccOut, "match.sh"), 0755)

	// 4. Config + messages
	copyFile(filepath.Join(ccSrc, "config.yml"), filepath.Join(ccOut, "config.yml"), "config.yml")
	copyFile(filepath.Join(ccSrc, "messages.yml"), filepath.Join(ccOut, "messages.yml"), "messages.yml")

	// 5. Plugin manifest
	copyFile(filepath.Join(ccSrc, "plugin.json"), filepath.Join(ccOut, ".claude-plugin", "plugin.json"), "plugin.json")

	// 6. .pluginignore + README
	copyFile(filepath.Join(ccSrc, ".pluginignore"), filepath.Join(ccOut, ".pluginignore"), ".pluginignore")
	copyFile(filepath.Join(ccSrc, "README.md"), filepath.Join(ccOut, "README.md"), "README.md")
}

// =============================================================================
// MARKETPLACE — shared, reads both plugin.json versions
// =============================================================================

func buildMarketplace(srcDir, repoRoot string) {
	hookerVersion := readVersion(filepath.Join(srcDir, "hooker"))
	ccVersion := readVersion(filepath.Join(srcDir, "cache-catcher"))

	marketplace := map[string]any{
		"name":  "treetank-marketplace",
		"owner": map[string]string{"name": "treetank"},
		"plugins": []map[string]string{
			{
				"name":        "hooker",
				"source":      "./hooker",
				"description": "Universal hook injection framework. Inject prompts, reminders, and guardrails into 25+ Claude Code hook events.",
				"version":     hookerVersion,
			},
			{
				"name":        "cache-catcher",
				"source":      "./cache-catcher",
				"description": "Monitor Claude Code cache health. Warns or blocks when cache writes exceed reads.",
				"version":     ccVersion,
			},
		},
	}

	data, err := json.MarshalIndent(marketplace, "", "  ")
	if err != nil {
		fatal("marketplace.json", "marshaling", err)
	}
	data = append(data, '\n')

	writeFile(filepath.Join(repoRoot, "marketplace.json"), data)
	fmt.Println("  marketplace.json: built (repo root)")
}

// =============================================================================
// SHARED BUILD FUNCTIONS
// =============================================================================

// --- Commands: Gonja templates ---

func buildCommands(pluginSrc, pluginOut string, ctx *exec.Context) {
	srcCommands := filepath.Join(pluginSrc, "commands")
	outCommands := filepath.Join(pluginOut, "commands")

	os.MkdirAll(outCommands, 0755)

	entries, err := os.ReadDir(srcCommands)
	if err != nil {
		fmt.Fprintf(os.Stderr, "  commands/: ERROR — %v\n", err)
		os.Exit(1)
	}

	hasTemplating := regexp.MustCompile(`\{[{%#]`)

	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") {
			continue
		}

		srcPath := filepath.Join(srcCommands, e.Name())
		outPath := filepath.Join(outCommands, e.Name())
		data, err := os.ReadFile(srcPath)
		if err != nil {
			fatal(e.Name(), "reading", err)
		}

		src := string(data)
		if !hasTemplating.MatchString(src) {
			writeFile(outPath, data)
			fmt.Printf("  commands/%s: copied\n", e.Name())
			continue
		}

		tpl, err := gonja.FromString(src)
		if err != nil {
			fatal("commands/"+e.Name(), "parsing", err)
		}

		result, err := tpl.ExecuteToString(ctx)
		if err != nil {
			fatal("commands/"+e.Name(), "rendering", err)
		}

		writeFile(outPath, []byte(result))
		fmt.Printf("  commands/%s: built\n", e.Name())
	}
}

// --- Scripts: Shell bundling ---
// Resolves `# @bundle path/to/file.sh` directives by inlining file contents.

func buildScripts(pluginSrc, pluginOut string) {
	srcScripts := filepath.Join(pluginSrc, "scripts")
	outScripts := filepath.Join(pluginOut, "scripts")

	entries, err := os.ReadDir(srcScripts)
	if err != nil {
		return
	}

	os.MkdirAll(outScripts, 0755)

	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".sh") {
			continue
		}

		srcPath := filepath.Join(srcScripts, e.Name())
		outPath := filepath.Join(outScripts, e.Name())

		result, err := bundleShell(srcPath, srcScripts)
		if err != nil {
			fatal("scripts/"+e.Name(), "bundling", err)
		}

		writeFile(outPath, []byte(result))
		os.Chmod(outPath, 0755)
		fmt.Printf("  scripts/%s: bundled\n", e.Name())
	}
}

func bundleShell(path, baseDir string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()

	var out strings.Builder
	scanner := bufio.NewScanner(file)
	bundleRe := regexp.MustCompile(`^#\s*@bundle\s+(.+)$`)

	for scanner.Scan() {
		line := scanner.Text()

		if m := bundleRe.FindStringSubmatch(line); m != nil {
			includePath := filepath.Join(baseDir, m[1])
			content, err := os.ReadFile(includePath)
			if err != nil {
				return "", fmt.Errorf("@bundle %s: %w", m[1], err)
			}
			// Strip leading comments/blank lines from included file
			text := strings.TrimSpace(string(content))
			out.WriteString(text)
			out.WriteString("\n\n")
		} else {
			out.WriteString(line)
			out.WriteString("\n")
		}
	}

	return out.String(), scanner.Err()
}

// --- Single file: gonja template or copy ---

func buildFile(srcPath, outPath, label string, ctx *exec.Context) {
	data, err := os.ReadFile(srcPath)
	if err != nil {
		if os.IsNotExist(err) {
			return
		}
		fatal(label, "reading", err)
	}

	src := string(data)
	hasTemplating := regexp.MustCompile(`\{[{%#]`).MatchString(src)

	if !hasTemplating {
		writeFile(outPath, data)
		fmt.Printf("  %s: copied\n", label)
		return
	}

	tpl, err := gonja.FromString(src)
	if err != nil {
		fatal(label, "parsing", err)
	}

	result, err := tpl.ExecuteToString(ctx)
	if err != nil {
		fatal(label, "rendering", err)
	}

	writeFile(outPath, []byte(result))
	fmt.Printf("  %s: built\n", label)
}

// --- Static copy ---

func copyDir(src, dst, label string) {
	if _, err := os.Stat(src); os.IsNotExist(err) {
		return
	}

	count := 0
	filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(src, path)
		target := filepath.Join(dst, rel)

		if info.IsDir() {
			os.MkdirAll(target, 0755)
			return nil
		}

		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		writeFile(target, data)
		// Preserve executable bit
		if info.Mode()&0111 != 0 {
			os.Chmod(target, 0755)
		}
		count++
		return nil
	})
	fmt.Printf("  %s/: %d files copied\n", label, count)
}

func copyFile(src, dst, label string) {
	if _, err := os.Stat(src); os.IsNotExist(err) {
		return
	}
	data, err := os.ReadFile(src)
	if err != nil {
		fatal(label, "reading", err)
	}
	os.MkdirAll(filepath.Dir(dst), 0755)
	writeFile(dst, data)
	fmt.Printf("  %s: copied\n", label)
}

// --- Read plugin version ---

func readVersion(pluginSrcDir string) string {
	data, err := os.ReadFile(filepath.Join(pluginSrcDir, "plugin.json"))
	if err != nil {
		return "unknown"
	}
	re := regexp.MustCompile(`"version"\s*:\s*"([^"]+)"`)
	m := re.FindSubmatch(data)
	if m != nil {
		return string(m[1])
	}
	return "unknown"
}

// --- Compile standalone executables for recipes ---

func compileExecutables(pluginSrc, pluginOut, version string) {
	// Load bundled helpers.sh
	helpersPath := filepath.Join(pluginOut, "scripts", "helpers.sh")
	helpersContent, err := os.ReadFile(helpersPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "  execute: WARNING — cannot read helpers.sh: %v\n", err)
		return
	}

	// Load multi-language helpers
	pyHelpersContent, _ := os.ReadFile(filepath.Join(pluginSrc, "helpers", "hooker_helpers.py"))
	jsHelpersContent, _ := os.ReadFile(filepath.Join(pluginSrc, "helpers", "hooker_helpers.js"))

	recipesDir := filepath.Join(pluginSrc, "recipes")
	entries, err := os.ReadDir(recipesDir)
	if err != nil {
		return
	}

	preamble := fmt.Sprintf(`#!/bin/bash
# Hooker standalone execute.sh — compiled from match script + helpers
# Can be used directly in .claude/settings.json without hooker plugin.
# Generated by: cd src && go run .
# Hooker version: %s
#
# Exit code translation (standalone has no inject.sh to catch codes):
#   exit 0 → ok (pass through)
#   exit 1 → skip/no-match → translated to exit 0 (not an error)
#   exit 2+ → real error → translated to exit 1 (Claude Code shows "hook error")

INPUT=$(cat)`, version) + `
HOOKER_EVENT=$(echo "$INPUT" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
HOOKER_CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
HOOKER_TRANSCRIPT=$(echo "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
export HOOKER_EVENT HOOKER_CWD HOOKER_TRANSCRIPT

`

	// Epilogue wraps the recipe body in _hooker_main, translates exit codes
	epilogue := `
# --- Exit code translation ---
_hooker_main() {
`

	epilogueEnd := `
}
_hooker_main
_EXIT=$?
if [ "$_EXIT" -eq 0 ]; then exit 0
elif [ "$_EXIT" -eq 1 ]; then exit 0   # skip/no-match → not an error
else exit 1                             # exit 2+ → real error
fi
`

	mdHandler := fmt.Sprintf(`#!/bin/bash
# Hooker standalone execute.sh — compiled from .md template
# Can be used directly in .claude/settings.json without hooker plugin.
# Generated by: cd src && go run .
# Hooker version: %s`, version) + `

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/%s"

ACTION=$(awk '/^---$/{n++; next} n==1 && /^type:/{gsub(/^type:[[:space:]]*/, ""); print; exit}' "$TEMPLATE")
CONTENT=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$TEMPLATE")
CONTENT=$(echo "$CONTENT" | sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba;}')
[ -z "$ACTION" ] && ACTION="inject"
[ -z "$CONTENT" ] && exit 0

case "$ACTION" in
    inject)
        cat <<INJECT_EOF
</local-command-stdout>

${CONTENT}

<local-command-stdout>
INJECT_EOF
        ;;
    *)
        echo "$CONTENT"
        ;;
esac
`

	count := 0
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		recipeDir := filepath.Join(recipesDir, e.Name())
		outDir := filepath.Join(pluginOut, "recipes", e.Name())

		hookFiles, _ := os.ReadDir(recipeDir)
		for _, hf := range hookFiles {
			name := hf.Name()

			// Compile .match.sh → .execute.sh
			if strings.HasSuffix(name, ".match.sh") {
				hookName := strings.TrimSuffix(name, ".match.sh")
				matchPath := filepath.Join(recipeDir, name)
				outPath := filepath.Join(outDir, hookName+".execute.sh")

				matchContent, err := os.ReadFile(matchPath)
				if err != nil {
					continue
				}

				// Remove shebang and source HOOKER_HELPERS line
				body := string(matchContent)
				body = regexp.MustCompile(`(?m)^#!.*\n`).ReplaceAllString(body, "")
				body = regexp.MustCompile(`(?m)^source\s+"\$\{HOOKER_HELPERS\}"\s*\n`).ReplaceAllString(body, "")
				// Remove INPUT=$(cat) — preamble handles it
				body = regexp.MustCompile(`(?m)^INPUT=\$\(cat\)\s*\n`).ReplaceAllString(body, "")
				body = strings.TrimSpace(body)
				body = regexp.MustCompile(`\bexit (\d+)`).ReplaceAllString(body, "return $1")

				var out strings.Builder
				out.WriteString(preamble)
				out.WriteString("# --- Inlined helpers ---\n")
				h := string(helpersContent)
				h = regexp.MustCompile(`(?m)^#!.*\n`).ReplaceAllString(h, "")
				out.WriteString(h)
				out.WriteString(epilogue)
				out.WriteString(body)
				out.WriteString(epilogueEnd)

				writeFile(outPath, []byte(out.String()))
				os.Chmod(outPath, 0755)
				count++
			}

			// Compile .match.py → .execute.py
			if strings.HasSuffix(name, ".match.py") && len(pyHelpersContent) > 0 {
				hookName := strings.TrimSuffix(name, ".match.py")
				matchPath := filepath.Join(recipeDir, name)
				outPath := filepath.Join(outDir, hookName+".execute.py")

				matchContent, err := os.ReadFile(matchPath)
				if err != nil {
					continue
				}

				body := string(matchContent)
				body = regexp.MustCompile(`(?m)^#!.*\n`).ReplaceAllString(body, "")
				body = regexp.MustCompile(`(?m)^from hooker_helpers import.*\n`).ReplaceAllString(body, "")
				body = regexp.MustCompile(`(?m)^import hooker_helpers.*\n`).ReplaceAllString(body, "")
				body = strings.TrimSpace(body)

				helpers := string(pyHelpersContent)
				helpers = regexp.MustCompile(`(?ms)^""".*?"""\n`).ReplaceAllString(helpers, "")
				helpers = regexp.MustCompile(`(?m)^import json\n`).ReplaceAllString(helpers, "")
				helpers = regexp.MustCompile(`(?m)^import sys\n`).ReplaceAllString(helpers, "")
				helpers = regexp.MustCompile(`(?m)^import os\n`).ReplaceAllString(helpers, "")
				helpers = strings.TrimSpace(helpers)

				compiled := fmt.Sprintf(`#!/usr/bin/env python3
# Hooker standalone execute.py — compiled from match script + helpers
# Can be used directly in .claude/settings.json without hooker plugin.
# Generated by: cd src && go run .
# Hooker version: %s
#
# Usage in settings.json:
#   { "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooker/{recipe}/%s.execute.py\"" }

import json
import sys
import os

# --- Inlined helpers ---
%s

# --- Recipe ---
def _hooker_main():
    %s

try:
    _hooker_main()
    sys.exit(0)
except SystemExit as e:
    code = e.code if isinstance(e.code, int) else 1
    if code <= 1:
        sys.exit(0)   # match or skip → not an error
    else:
        sys.exit(1)   # real error → Claude Code shows "hook error"
`, version, hookName, helpers, strings.ReplaceAll(body, "\n", "\n    "))

				writeFile(outPath, []byte(compiled))
				os.Chmod(outPath, 0755)
				count++
			}

			// Compile .match.js → .execute.js (also used for .match.ts → .execute.js)
			if (strings.HasSuffix(name, ".match.js") || strings.HasSuffix(name, ".match.ts")) && len(jsHelpersContent) > 0 {
				ext := filepath.Ext(name)
				hookName := strings.TrimSuffix(strings.TrimSuffix(name, ".match.js"), ".match.ts")
				matchPath := filepath.Join(recipeDir, name)
				outPath := filepath.Join(outDir, hookName+".execute.js")

				matchContent, err := os.ReadFile(matchPath)
				if err != nil {
					continue
				}

				body := string(matchContent)
				body = regexp.MustCompile(`(?m)^#!.*\n`).ReplaceAllString(body, "")
				varNameMatch := regexp.MustCompile(`(?m)^const (\w+) = require\(['"]hooker_helpers['"]\)`).FindStringSubmatch(body)
				body = regexp.MustCompile(`(?m)^const .+ = require\(['"]hooker_helpers['"]\);?\n`).ReplaceAllString(body, "")
				body = regexp.MustCompile(`(?m)^const \{[^}]+\} = require\(['"]hooker_helpers['"]\);?\n`).ReplaceAllString(body, "")
				body = regexp.MustCompile(`(?m)^import .+ from ['"]hooker_helpers['"];?\n`).ReplaceAllString(body, "")
				if len(varNameMatch) > 1 {
					prefix := varNameMatch[1] + "."
					body = strings.ReplaceAll(body, prefix, "")
				}
				if ext == ".ts" {
					body = regexp.MustCompile(`:\s*(string|number|boolean|any|object|void|Record<[^>]+>|[A-Z]\w*(?:\[\])?)\s*=`).ReplaceAllString(body, " =")
					body = regexp.MustCompile(`(?m)^import .+ from ['"][^'"]+['"];?\n`).ReplaceAllString(body, "")
				}
				body = strings.TrimSpace(body)

				helpers := string(jsHelpersContent)
				helpers = regexp.MustCompile(`(?ms)^/\*\*.*?\*/\n*`).ReplaceAllString(helpers, "")
				helpers = regexp.MustCompile(`(?m)^const fs = require\('fs'\);?\n`).ReplaceAllString(helpers, "")
				helpers = regexp.MustCompile(`(?ms)^module\.exports = \{[^}]*\};?\n?`).ReplaceAllString(helpers, "")
				helpers = strings.TrimSpace(helpers)

				compiled := fmt.Sprintf(`#!/usr/bin/env node
// Hooker standalone execute.js — compiled from match script + helpers
// Can be used directly in .claude/settings.json without hooker plugin.
// Generated by: cd src && go run .
// Hooker version: %s
//
// Usage in settings.json:
//   { "command": "node \"$CLAUDE_PROJECT_DIR/.claude/hooker/{recipe}/%s.execute.js\"" }

const fs = require('fs');

// --- Exit code translation ---
const _origExit = process.exit;
process.exit = function(code) {
    if (typeof code === 'number' && code <= 1) _origExit(0);   // match or skip
    else _origExit(1);                                          // real error
};

// --- Inlined helpers ---
%s

// --- Recipe ---
%s
`, version, hookName, helpers, body)

				writeFile(outPath, []byte(compiled))
				os.Chmod(outPath, 0755)
				count++
			}

			// Compile .md (without matching .match.*) → .execute.sh
			if strings.HasSuffix(name, ".md") {
				hookName := strings.TrimSuffix(name, ".md")
				matchExists := false
				for _, check := range hookFiles {
					cn := check.Name()
					if strings.HasPrefix(cn, hookName+".match.") {
						matchExists = true
						break
					}
				}
				if matchExists {
					continue
				}

				outPath := filepath.Join(outDir, hookName+".execute.sh")
				compiled := fmt.Sprintf(mdHandler, name)
				writeFile(outPath, []byte(compiled))
				os.Chmod(outPath, 0755)
				count++
			}
		}
	}
	fmt.Printf("  recipes/: %d standalone executables compiled\n", count)
}

// =============================================================================
// HELPERS
// =============================================================================

func writeFile(path string, data []byte) {
	if err := os.WriteFile(path, data, 0644); err != nil {
		fmt.Fprintf(os.Stderr, "ERROR writing %s: %v\n", path, err)
		os.Exit(1)
	}
}

func fatal(name, action string, err error) {
	fmt.Fprintf(os.Stderr, "  %s: ERROR %s — %v\n", name, action, err)
	os.Exit(1)
}

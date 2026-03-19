package main

import (
	"bufio"
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
	srcDir, _ := os.Getwd()
	if _, err := os.Stat(filepath.Join(srcDir, "build.go")); err != nil {
		srcDir, _ = filepath.Abs(filepath.Dir(os.Args[0]))
	}

	rootDir := filepath.Join(srcDir, "..")

	recipes := generators.LoadRecipes(srcDir)

	ctx := exec.NewContext(map[string]any{
		"recipes":        recipes,
		"categories":     generators.GroupByCategory(recipes),
		"uncoveredHooks": generators.UncoveredHooks(recipes),
		"coveredHooks":   generators.CoveredHooks(recipes),
		"allHooks":       generators.AllHooks(),
	})

	fmt.Println("Building Hooker plugin...")

	// 1. Commands — gonja templates
	buildCommands(srcDir, rootDir, ctx)

	// 2. Scripts — shell bundling (@bundle directives)
	buildScripts(srcDir, rootDir)

	// 3. Recipes — copy as-is + compile execute.sh
	copyDir(filepath.Join(srcDir, "recipes"), filepath.Join(rootDir, "recipes"), "recipes")
	compileExecutables(srcDir, rootDir)
	copyDir(filepath.Join(srcDir, "hooks"), filepath.Join(rootDir, "hooks"), "hooks")
	copyDir(filepath.Join(srcDir, "templates"), filepath.Join(rootDir, "templates"), "templates")

	// 4. Plugin manifest + marketplace
	copyFile(filepath.Join(srcDir, "plugin.json"), filepath.Join(rootDir, ".claude-plugin", "plugin.json"), "plugin.json")
	copyFile(filepath.Join(srcDir, "marketplace.json"), filepath.Join(rootDir, ".claude-plugin", "marketplace.json"), "marketplace.json")

	// 5. .pluginignore
	copyFile(filepath.Join(srcDir, ".pluginignore"), filepath.Join(rootDir, ".pluginignore"), ".pluginignore")

	// 6. README.md — gonja template at root level
	buildFile(filepath.Join(srcDir, "README.md"), filepath.Join(rootDir, "README.md"), "README.md", ctx)

	fmt.Println("Done.")
}

// --- Commands: Gonja templates ---

func buildCommands(srcDir, rootDir string, ctx *exec.Context) {
	srcCommands := filepath.Join(srcDir, "commands")
	outCommands := filepath.Join(rootDir, "commands")

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

func buildScripts(srcDir, rootDir string) {
	srcScripts := filepath.Join(srcDir, "scripts")
	outScripts := filepath.Join(rootDir, "scripts")

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

// --- Compile execute.sh for standalone recipes ---

func compileExecutables(srcDir, rootDir string) {
	// Load bundled helpers.sh
	helpersPath := filepath.Join(rootDir, "scripts", "helpers.sh")
	helpersContent, err := os.ReadFile(helpersPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "  execute: WARNING — cannot read helpers.sh: %v\n", err)
		return
	}

	recipesDir := filepath.Join(srcDir, "recipes")
	entries, err := os.ReadDir(recipesDir)
	if err != nil {
		return
	}

	preamble := `#!/bin/bash
# Hooker standalone execute.sh — compiled from match script + helpers
# Can be used directly in .claude/settings.json without hooker plugin.
# Generated by: cd src && go run .

INPUT=$(cat)
HOOKER_EVENT=$(echo "$INPUT" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
HOOKER_CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
HOOKER_TRANSCRIPT=$(echo "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
export HOOKER_EVENT HOOKER_CWD HOOKER_TRANSCRIPT

`

	mdHandler := `#!/bin/bash
# Hooker standalone execute.sh — compiled from .md template
# Can be used directly in .claude/settings.json without hooker plugin.
# Generated by: cd src && go run .

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
		outDir := filepath.Join(rootDir, "recipes", e.Name())

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
				// Remove standalone HOOKER_NO_REFACTOR check — preamble could add it but keeping it is fine
				body = strings.TrimSpace(body)

				var out strings.Builder
				out.WriteString(preamble)
				out.WriteString("# --- Inlined helpers ---\n")
				// Strip shebang from helpers
				h := string(helpersContent)
				h = regexp.MustCompile(`(?m)^#!.*\n`).ReplaceAllString(h, "")
				out.WriteString(h)
				out.WriteString("\n# --- Recipe logic ---\n")
				out.WriteString(body)
				out.WriteString("\n")

				writeFile(outPath, []byte(out.String()))
				os.Chmod(outPath, 0755)
				count++
			}

			// Compile .md (without matching .match.sh) → .execute.sh
			if strings.HasSuffix(name, ".md") {
				hookName := strings.TrimSuffix(name, ".md")
				matchExists := false
				for _, check := range hookFiles {
					if check.Name() == hookName+".match.sh" {
						matchExists = true
						break
					}
				}
				if matchExists {
					continue // match.sh takes precedence, already compiled above
				}

				outPath := filepath.Join(outDir, hookName+".execute.sh")
				compiled := fmt.Sprintf(mdHandler, name)
				writeFile(outPath, []byte(compiled))
				os.Chmod(outPath, 0755)
				count++
			}
		}
	}
	fmt.Printf("  recipes/: %d execute.sh compiled\n", count)
}

// --- Helpers ---

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

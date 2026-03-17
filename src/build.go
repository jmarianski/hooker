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

	recipes := generators.LoadRecipes(rootDir)

	ctx := exec.NewContext(map[string]any{
		"recipes":        recipes,
		"uncoveredHooks": generators.UncoveredHooks(recipes),
		"coveredHooks":   generators.CoveredHooks(recipes),
		"allHooks":       generators.AllHooks(),
	})

	fmt.Println("Building Hooker plugin...")

	// 1. Commands — gonja templates
	buildCommands(srcDir, rootDir, ctx)

	// 2. Scripts — shell bundling (@bundle directives)
	buildScripts(srcDir, rootDir)

	// 3. Static dirs — copy as-is
	copyDir(filepath.Join(srcDir, "recipes"), filepath.Join(rootDir, "recipes"), "recipes")
	copyDir(filepath.Join(srcDir, "hooks"), filepath.Join(rootDir, "hooks"), "hooks")
	copyDir(filepath.Join(srcDir, "templates"), filepath.Join(rootDir, "templates"), "templates")

	// 4. Plugin manifest
	copyFile(filepath.Join(srcDir, "plugin.json"), filepath.Join(rootDir, ".claude-plugin", "plugin.json"), "plugin.json")

	// 5. .pluginignore
	copyFile(filepath.Join(srcDir, ".pluginignore"), filepath.Join(rootDir, ".pluginignore"), ".pluginignore")

	fmt.Println("Done.")
}

// --- Commands: Gonja templates ---

func buildCommands(srcDir, rootDir string, ctx *exec.Context) {
	srcCommands := filepath.Join(srcDir, "commands")
	outCommands := filepath.Join(rootDir, "commands")

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

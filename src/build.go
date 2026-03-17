package main

import (
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
	// Find src dir (where this binary / build.go lives)
	srcDir, _ := os.Getwd()
	if _, err := os.Stat(filepath.Join(srcDir, "build.go")); err != nil {
		srcDir, _ = filepath.Abs(filepath.Dir(os.Args[0]))
	}

	rootDir := filepath.Join(srcDir, "..")
	srcCommands := filepath.Join(srcDir, "commands")
	outCommands := filepath.Join(rootDir, "commands")

	// Load data
	recipes := generators.LoadRecipes(rootDir)

	// Build context with template globals
	ctx := exec.NewContext(map[string]any{
		"recipes":        recipes,
		"uncoveredHooks": generators.UncoveredHooks(recipes),
		"coveredHooks":   generators.CoveredHooks(recipes),
		"allHooks":       generators.AllHooks(),
	})

	fmt.Println("Building skills...")

	entries, err := os.ReadDir(srcCommands)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading %s: %v\n", srcCommands, err)
		os.Exit(1)
	}

	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") {
			continue
		}

		srcPath := filepath.Join(srcCommands, e.Name())
		outPath := filepath.Join(outCommands, e.Name())

		data, err := os.ReadFile(srcPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  %s: ERROR reading — %v\n", e.Name(), err)
			os.Exit(1)
		}

		src := string(data)

		// Check if file has templating
		hasTemplating := regexp.MustCompile(`\{[{%#]`).MatchString(src)
		if !hasTemplating {
			if err := os.WriteFile(outPath, data, 0644); err != nil {
				fmt.Fprintf(os.Stderr, "  %s: ERROR writing — %v\n", e.Name(), err)
				os.Exit(1)
			}
			fmt.Printf("  %s: copied\n", e.Name())
			continue
		}

		tpl, err := gonja.FromString(src)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  %s: ERROR parsing — %v\n", e.Name(), err)
			os.Exit(1)
		}

		result, err := tpl.ExecuteToString(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  %s: ERROR rendering — %v\n", e.Name(), err)
			os.Exit(1)
		}

		if err := os.WriteFile(outPath, []byte(result), 0644); err != nil {
			fmt.Fprintf(os.Stderr, "  %s: ERROR writing — %v\n", e.Name(), err)
			os.Exit(1)
		}
		fmt.Printf("  %s: built\n", e.Name())
	}

	fmt.Println("Done.")
}

package generators

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type Recipe struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Hooks       []string `json:"hooks"`
}

var allHooks = []string{
	"SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
	"PostToolUse", "PostToolUseFailure", "Notification", "SubagentStart",
	"SubagentStop", "Stop", "TeammateIdle", "TaskCompleted",
	"InstructionsLoaded", "ConfigChange", "WorktreeCreate", "WorktreeRemove",
	"PreCompact", "PostCompact", "Elicitation", "ElicitationResult", "SessionEnd",
}

func LoadRecipes(rootDir string) []Recipe {
	recipesDir := filepath.Join(rootDir, "recipes")
	entries, err := os.ReadDir(recipesDir)
	if err != nil {
		return nil
	}

	var recipes []Recipe
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		jsonPath := filepath.Join(recipesDir, e.Name(), "recipe.json")
		data, err := os.ReadFile(jsonPath)
		if err != nil {
			continue
		}
		var r Recipe
		if err := json.Unmarshal(data, &r); err != nil {
			continue
		}
		r.ID = e.Name()
		recipes = append(recipes, r)
	}

	sort.Slice(recipes, func(i, j int) bool {
		return recipes[i].ID < recipes[j].ID
	})
	return recipes
}

func CoveredHooks(recipes []Recipe) []string {
	seen := map[string]bool{}
	for _, r := range recipes {
		for _, h := range r.Hooks {
			seen[h] = true
		}
	}
	var out []string
	for _, h := range allHooks {
		if seen[h] {
			out = append(out, h)
		}
	}
	return out
}

func UncoveredHooks(recipes []Recipe) []string {
	covered := map[string]bool{}
	for _, r := range recipes {
		for _, h := range r.Hooks {
			covered[h] = true
		}
	}
	var out []string
	for _, h := range allHooks {
		if !covered[h] {
			out = append(out, h)
		}
	}
	return out
}

func AllHooks() []string {
	return allHooks
}

// JoinStrings for use in templates
func JoinStrings(items []string, sep string) string {
	return strings.Join(items, sep)
}

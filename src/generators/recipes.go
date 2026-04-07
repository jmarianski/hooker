package generators

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type PluginConfig struct {
	Output string `json:"output"` // output directory name, e.g. "cache-catcher"
}

type Attribution struct {
	Type    string `json:"type"`
	Author  string `json:"author"`
	License string `json:"license"`
	URL     string `json:"url,omitempty"`
}

type Recipe struct {
	ID            string              `json:"id"`
	Name          string              `json:"name"`
	Description   string              `json:"description"`
	Version       string              `json:"version,omitempty"`
	Hooks         []string            `json:"hooks"`
	Matchers      map[string]string   `json:"matchers,omitempty"`
	Category      string              `json:"category"`
	Attribution   *Attribution        `json:"attribution,omitempty"`
	Plugin        *PluginConfig       `json:"plugin,omitempty"`
	Compatibility *RecipeCompatibility `json:"compatibility,omitempty"`
}

type RecipeCompatibility struct {
	Claude string `json:"claude,omitempty"`
	Codex  string `json:"codex,omitempty"`
}

var allHooks = []string{
	// Base hooks — in plugin hooks.json, supported since CC 2.1.68
	"SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
	"PostToolUse", "PostToolUseFailure", "Notification", "SubagentStart",
	"SubagentStop", "Stop", "TeammateIdle", "TaskCompleted",
	"ConfigChange", "WorktreeCreate", "WorktreeRemove",
	"PreCompact", "Elicitation", "ElicitationResult", "SessionEnd", "Setup",
	// Overflow hooks — added via settings.json, version-gated
	"InstructionsLoaded", // CC >= 2.1.69
	"StopFailure",       // CC >= 2.1.78
	"PostCompact",       // CC >= 2.1.78
	"CwdChanged",        // CC >= 2.1.83
	"FileChanged",       // CC >= 2.1.83
	"TaskCreated",       // CC >= 2.1.84
	"PermissionDenied",  // CC >= 2.1.89
}

var codexHooks = []string{
	"SessionStart",
	"UserPromptSubmit",
	"PreToolUse",
	"PostToolUse",
	"Stop",
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
		applyDefaultCompatibility(&r)
		recipes = append(recipes, r)
	}

	sort.Slice(recipes, func(i, j int) bool {
		return recipes[i].ID < recipes[j].ID
	})
	return recipes
}

func applyDefaultCompatibility(r *Recipe) {
	if r.Compatibility == nil {
		r.Compatibility = &RecipeCompatibility{}
	}
	if strings.TrimSpace(r.Compatibility.Claude) == "" {
		r.Compatibility.Claude = "native"
	}
	if strings.TrimSpace(r.Compatibility.Codex) == "" {
		if recipeUsesOnlyHooks(r.Hooks, codexHooks) {
			r.Compatibility.Codex = "native"
		} else {
			r.Compatibility.Codex = "unsupported"
		}
	}
}

func recipeUsesOnlyHooks(recipeHooks, supportedHooks []string) bool {
	if len(recipeHooks) == 0 {
		return true
	}
	supported := make(map[string]bool, len(supportedHooks))
	for _, hook := range supportedHooks {
		supported[hook] = true
	}
	for _, hook := range recipeHooks {
		if !supported[hook] {
			return false
		}
	}
	return true
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

func CodexHooks() []string {
	return codexHooks
}

type CategoryGroup struct {
	ID      string   `json:"id"`
	Label   string   `json:"label"`
	Recipes []Recipe `json:"recipes"`
}

var categoryLabels = map[string]string{
	"safety":      "Safety",
	"refactoring": "Refactoring",
	"workflow":    "Workflow",
	"context":     "Context",
	"quality":     "Quality",
	"monitoring":  "Monitoring",
}

var categoryOrder = []string{"safety", "refactoring", "workflow", "context", "quality", "monitoring"}

func GroupByCategory(recipes []Recipe) []CategoryGroup {
	groups := map[string][]Recipe{}
	for _, r := range recipes {
		cat := r.Category
		if cat == "" {
			cat = "other"
		}
		groups[cat] = append(groups[cat], r)
	}

	var out []CategoryGroup
	for _, id := range categoryOrder {
		if rs, ok := groups[id]; ok {
			label := categoryLabels[id]
			if label == "" {
				label = id
			}
			out = append(out, CategoryGroup{ID: id, Label: label, Recipes: rs})
		}
	}
	// Any uncategorized
	for cat, rs := range groups {
		found := false
		for _, id := range categoryOrder {
			if id == cat {
				found = true
				break
			}
		}
		if !found {
			out = append(out, CategoryGroup{ID: cat, Label: cat, Recipes: rs})
		}
	}
	return out
}

// JoinStrings for use in templates
func JoinStrings(items []string, sep string) string {
	return strings.Join(items, sep)
}

const fs = require('fs');
const path = require('path');

const RECIPES_DIR = path.join(__dirname, '../../recipes');

const ALL_HOOKS = [
  'SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest',
  'PostToolUse', 'PostToolUseFailure', 'Notification', 'SubagentStart',
  'SubagentStop', 'Stop', 'TeammateIdle', 'TaskCompleted',
  'InstructionsLoaded', 'ConfigChange', 'WorktreeCreate', 'WorktreeRemove',
  'PreCompact', 'PostCompact', 'Elicitation', 'ElicitationResult', 'SessionEnd'
];

function loadRecipes() {
  const dirs = fs.readdirSync(RECIPES_DIR).filter(d =>
    fs.statSync(path.join(RECIPES_DIR, d)).isDirectory()
  );

  return dirs.map(dir => {
    const jsonPath = path.join(RECIPES_DIR, dir, 'recipe.json');
    if (!fs.existsSync(jsonPath)) return null;
    const data = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
    return { id: dir, ...data };
  }).filter(Boolean);
}

function recipes() {
  return loadRecipes();
}

function coveredHooks() {
  const covered = new Set();
  for (const r of loadRecipes()) {
    (r.hooks || []).forEach(h => covered.add(h));
  }
  return [...covered];
}

function uncoveredHooks() {
  const covered = coveredHooks();
  return ALL_HOOKS.filter(h => !covered.includes(h));
}

module.exports = { recipes, coveredHooks, uncoveredHooks, ALL_HOOKS };

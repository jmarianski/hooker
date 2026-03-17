const fs = require('fs');
const path = require('path');
const nunjucks = require('nunjucks');

const SRC_DIR = __dirname;
const ROOT_DIR = path.join(SRC_DIR, '..');
const SRC_COMMANDS = path.join(SRC_DIR, 'commands');
const OUT_COMMANDS = path.join(ROOT_DIR, 'commands');
const GENERATORS_DIR = path.join(SRC_DIR, 'generators');

// --- Auto-load generators ---
// Each .js file in generators/ exports functions that become template globals.
function loadGenerators() {
  const globals = {};
  if (!fs.existsSync(GENERATORS_DIR)) return globals;

  for (const file of fs.readdirSync(GENERATORS_DIR)) {
    if (!file.endsWith('.js')) continue;
    const mod = require(path.join(GENERATORS_DIR, file));
    for (const [name, fn] of Object.entries(mod)) {
      if (typeof fn === 'function') {
        globals[name] = fn;
      } else {
        globals[name] = fn;
      }
    }
  }
  return globals;
}

// --- Setup nunjucks ---
const env = new nunjucks.Environment(
  new nunjucks.FileSystemLoader(SRC_COMMANDS, { noCache: true }),
  { autoescape: false, trimBlocks: true, lstripBlocks: true }
);

// Register all generator functions as globals
const globals = loadGenerators();
for (const [name, value] of Object.entries(globals)) {
  env.addGlobal(name, value);
}

// --- Custom filters ---
env.addFilter('mdtable', (items, columns) => {
  // columns: [{key, header}, ...]
  const header = '| ' + columns.map(c => c.header).join(' | ') + ' |';
  const sep = '| ' + columns.map(() => '---').join(' | ') + ' |';
  const rows = items.map(item =>
    '| ' + columns.map(c => {
      const val = typeof c.key === 'function' ? c.key(item) : item[c.key];
      return val || '';
    }).join(' | ') + ' |'
  );
  return [header, sep, ...rows].join('\n');
});

// --- Build ---
console.log('Building skills...');

const srcFiles = fs.readdirSync(SRC_COMMANDS).filter(f => f.endsWith('.md'));

for (const file of srcFiles) {
  const src = fs.readFileSync(path.join(SRC_COMMANDS, file), 'utf8');
  const hasTemplating = /\{[{%#]/.test(src);

  if (!hasTemplating) {
    // Static file — just copy
    fs.copyFileSync(path.join(SRC_COMMANDS, file), path.join(OUT_COMMANDS, file));
    console.log(`  ${file}: copied`);
    continue;
  }

  try {
    const result = env.renderString(src);
    fs.writeFileSync(path.join(OUT_COMMANDS, file), result);
    console.log(`  ${file}: built`);
  } catch (err) {
    console.error(`  ${file}: ERROR — ${err.message}`);
    process.exit(1);
  }
}

console.log('Done.');

# src/

Build system for Hooker plugin skills. NOT part of the runtime plugin — see `.pluginignore`.

## Setup

```bash
cd src && npm install
```

## Build

```bash
cd src && npm run build
```

Compiles `src/commands/*.md` (Nunjucks templates) → `commands/` (output).
Static skills without a source in `src/commands/` are untouched.

## Structure

- `build.js` — main build script, auto-loads generators
- `commands/*.md` — source templates (Nunjucks syntax)
- `generators/*.js` — auto-loaded functions available in templates

## Writing templates

Templates use [Nunjucks](https://mozilla.github.io/nunjucks/) syntax:

```markdown
{% for r in recipes() %}
| `{{ r.id }}` | {{ r.hooks | join(', ') }} | {{ r.description }} |
{% endfor %}
```

## Adding a generator

Create `generators/myfeature.js`:

```js
module.exports = {
  myFunction() {
    return 'computed value';
  }
};
```

All exported functions/values are auto-registered as Nunjucks globals.
Use in templates: `{{ myFunction() }}`.

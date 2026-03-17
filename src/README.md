# src/

Build system for Hooker plugin skills. NOT part of the runtime plugin — see `.pluginignore`.

## Build

```bash
cd src && go run .
```

Compiles `src/commands/*.md` (Gonja templates) → `commands/` (output).
Static skills without a source in `src/commands/` are untouched.

## Structure

- `build.go` — main build script
- `commands/*.md` — source templates (Gonja/Jinja2 syntax)
- `generators/*.go` — data loaders providing template variables

## Writing templates

Templates use [Gonja](https://github.com/NikolaLohinski/gonja) (Jinja2 for Go):

```markdown
{%- for r in recipes %}
| `{{ r.ID }}` | {{ r.Hooks | join(d=", ") }} | {{ r.Description }} |
{%- endfor %}
```

## Adding a generator

Add exported functions/data to `generators/*.go`. They're registered as template
variables in `build.go`'s context map.

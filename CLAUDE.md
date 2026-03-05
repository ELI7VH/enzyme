# NZYM — Claude Plugin

## What This Is

NZYM (CLI: `enzyme`) is a Claude Code plugin that generates LLM-optimized folder digests. Instead of globbing and reading every file in a directory, read one `.enzyme` file and know everything. The digest is regenerated, never hand-edited.

## Plugin Structure

```
.claude-plugin/plugin.json  — Plugin metadata
agents/
  digest-generator.md       — Generate .enzyme digests for folders
commands/
  digest.md                 — /enzyme:digest — generate digest for a path
  read.md                   — /enzyme:read — read and interpret a .enzyme file
skills/
  folder-context.md         — Proactive: read .enzyme when entering folders
hooks/
  hooks.json                — SessionStart: check for stale digests
bin/
  enzyme.sh                 — CLI script (zero-dep bash)
```

## Commands

| Command | Description |
|---------|-------------|
| `/enzyme:digest <path>` | Generate a `.enzyme` digest for the target folder |
| `/enzyme:read <path>` | Read and summarize a `.enzyme` file |

## Key Principle

NZYM breaks down complex structures into absorbable forms. One file, full context.

## Configuration

Place `.enzyme.yml` at repo root or per-folder:

```yaml
version: 1
targets:
  - path: src/
    recursive: true
    ignore: ["node_modules", "*.test.*"]
summarizer:
  mode: deterministic    # or "llm" for API-powered summaries
inline_below_lines: 50
format: xml
output_file: .enzyme
```

## Version

Bump version in `.claude-plugin/plugin.json` for any change. Follow semver.

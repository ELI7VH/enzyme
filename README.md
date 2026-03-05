# enzyme

> Auto-generated, LLM-optimized folder digests. Machine-first. Zero maintenance.

Enzymes break down complex structures into absorbable forms. This tool does exactly that — breaks a folder of files into a flat XML digest that an LLM can absorb in one shot.

## Why

Without enzyme, an LLM entering a 20-file folder needs 21 tool calls (glob + read each). With enzyme, it reads one `.enzyme` file and knows everything. 95% byte compression. One read instead of many.

## Install

### As a Claude Code Plugin

```bash
/plugin marketplace add ELI7VH/enzyme
/plugin install enzyme
```

### Standalone CLI

```bash
git clone https://github.com/ELI7VH/enzyme.git
chmod +x enzyme/bin/enzyme.sh
enzyme/bin/enzyme.sh ./your-folder
```

## Usage

```bash
# Generate digest for a folder
enzyme.sh ./src

# Multiple folders
enzyme.sh ./src ./docs ./scripts

# Custom inline threshold (default: 50 lines)
enzyme.sh --inline 80 ./src

# Custom output filename
enzyme.sh --output digest.xml ./src
```

## Output

```xml
<enzyme folder="src" files="12" bytes="45000" lines="1200" generated="2026-03-05T21:57:13Z" mode="deterministic" version="0.1.0">
<file name="small.ts" lines="30" bytes="800" modified="2026-03-05" mode="inline">
// full file content inlined for small files
export const add = (a: number, b: number) => a + b
</file>
<file name="big.ts" lines="300" bytes="12000" modified="2026-03-04" keywords="audio,buffer,process,sample">
First meaningful line extracted as summary for large files.
</file>
</enzyme>
```

- **Small files** (under threshold): full content inlined
- **Large files** (over threshold): first meaningful line + top keywords by frequency
- **Binary files**: skipped
- **Dotfiles**: skipped

## Configuration

Optional `.enzyme.yml` at repo root or per-folder:

```yaml
version: 1
inline_below_lines: 50
format: xml
output_file: .enzyme
```

## Claude Code Plugin

When installed as a Claude plugin, enzyme provides:

| Component | Purpose |
|-----------|---------|
| `/enzyme:digest <path>` | Generate a digest |
| `/enzyme:read <path>` | Read and interpret a digest |
| Folder context skill | Auto-read `.enzyme` when entering folders |
| Digest generator agent | Knows how to create and manage digests |

## Design Principles

- **Generated, not maintained** — script produces it, humans never touch it
- **Lossy on purpose** — enough for an LLM to decide what to deep-read
- **Flat** — no nesting, no links, everything inline
- **Tagged** — XML delimiters for predictable LLM parsing
- **Zero-dep** — bash only, works everywhere

## Proof of Work

Built during a [WaveLoop](https://waveloop.app) development session. The `cloudy-ideas/` folder (10 files, 66KB) compressed to 2.9KB (95% reduction) with full context preserved.

## License

MIT

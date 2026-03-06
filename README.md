# NZYM

*formerly enzyme*

> Auto-generated, LLM-optimized folder digests. Machine-first. Zero maintenance.

Enzymes break down complex structures into absorbable forms. NZYM does exactly that — breaks a folder of files into a flat XML digest that an LLM can absorb in one shot. The CLI command is `enzyme` (via `enzyme.sh`), the output file is `.enzyme`, but the tool identity is **NZYM**.

## Why

Without nzym, an LLM entering a 20-file folder needs 21 tool calls (glob + read each). With nzym, it reads one `.enzyme` file and knows everything. 95% byte compression. One read instead of many.

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

When installed as a Claude plugin, nzym provides:

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

## Benchmarks

Tested across 5 utility folders, 2 production codebases, and 3 algorithmic compression baselines. Full results in [BENCHMARKS.md](BENCHMARKS.md).

| Metric | Result |
|--------|--------|
| Average compression | 82-89% |
| Context accuracy | 96.7% (14.5/15 questions answered correctly from digest alone) |
| vs gzip -9 | 2.4x better reduction while remaining LLM-readable |
| vs zstd -19 | 2.4x better (11.6% vs 28.4% of raw) |
| Code pattern preservation | Hooks/configs/utilities: 100%. Large components: architectural awareness only |
| Optimal inline threshold | 50 lines (confirmed via sweep from 20-150) |

### Environmental Impact (per developer/year)

| Metric | Savings |
|--------|---------|
| Tokens saved | 1.97 billion |
| Energy | 19.7 kWh |
| Water | 35.5 liters (71 bottles) |
| At 100K devs | 1.97 GWh + 1.4 Olympic pools of water |

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the full vision: strict vs delulu modes, cross-dimensional pattern matching, pattern deviation detection, Obsidian cross-system sync, LLM-powered compression inserts.

## Tests

```bash
bash tests/test-enzyme.sh
# 19/19 passing
```

## Bonus: nzym-chat

Digests Claude Code conversation transcripts (JSONL) into structured XML summaries. Extracts user messages, assistant responses, files modified, tools used, and errors.

```bash
# Digest all conversations on the machine
bin/nzym-chat.sh ./chat-digests --all

# Digest specific transcripts
bin/nzym-chat.sh ./out session1.jsonl session2.jsonl
```

Real-world result: 96MB of conversation history → 450KB of queryable digests (99.5% compression).

## Proof of Work

Built during a [WaveLoop](https://waveloop.app) development session. Benchmarked across 7 real-world codebases covering ~460KB of source code.

## License

MIT

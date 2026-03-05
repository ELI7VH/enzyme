# NZYM Roadmap

> Brain dump → roadmap. Captured during the benchmarking session 2026-03-05 MST.

---

## Shipped (v0.1.0)

- [x] Zero-dep bash CLI (`enzyme.sh`)
- [x] Per-folder XML digests (`.enzyme`)
- [x] Two-mode compression: inline small files, summarize large files
- [x] Keyword extraction with stop-word filtering
- [x] `.enzyme.yml` config support
- [x] Claude Code plugin (agents, commands, skills)
- [x] Negative compression auto-skip
- [x] Test suite (19/19 passing)
- [x] Benchmarks: semantic, algorithmic, competitive, environmental

---

## Near-term

### Recursive Mode (`--recursive` / `-r`)
Walk subdirectories and generate `.enzyme` per directory. Current depth-1 limitation requires manual per-directory invocation. Essential for real codebases.

### Language-Aware Stop Words
Filter JS/TS noise tokens (`const`, `import`, `var`, `return`, `div`, `function`, `export`, `default`) from keyword extraction alongside English stop words. Currently these dominate every file and dilute domain signal.

### Export Symbol Extraction
For TypeScript/JavaScript files, extract exported names (functions, components, types, constants) as a secondary metadata field. `exports="Timeline,TimelineEntry,kindColor"` provides more context than keyword frequency.

### Cross-System Sync (Obsidian / iCloud)
Generate `.enzyme` digests inside iCloud-synced folders (Obsidian vault). Machine A runs NZYM, iCloud propagates the digests, Machine B (or cloud Claude) reads them. The Obsidian vault has 581 .md files across 166 folders — digesting those gives any Claude session on any device instant vault awareness from a handful of reads instead of 581 file operations.

Extends to: GitHub Codespaces (commit `.enzyme`), SSH sessions (`scp` the digest), cloud Claude chats (paste content), CI/CD pipelines (generate as build artifact).

### Root-Scope Mode
Run NZYM across an entire development machine (`~/repos/*`). The user's workspace: 20 repos, 14,695 text files, 7.6 MB source, 953 code folders. Full-scope digestion would produce a meta-index of the entire creative/engineering output.

**Implementation:** A wrapper script or `--scope ~/repos` flag that walks all repos, skipping node_modules/.git, and generates per-folder digests. Produces a root-level `.enzyme-index` that maps folder → digest location → key stats.

---

## Medium-term

### Strict Mode (Code Conventions)
Digest mode optimized for code pattern recognition. Beyond keywords, extract:
- Import patterns (what libraries does this codebase use?)
- File naming conventions (PascalCase components? kebab-case utils?)
- Export patterns (default vs named, barrel files)
- State management patterns (hooks, providers, stores)
- Folder structure conventions

An LLM reading a strict-mode digest should be able to create new files that follow every established convention without being told.

### Delulu Mode (Creative Associations)
Digest mode optimized for wild, cross-domain associations. Instead of compressing for accuracy, compress for serendipity:
- Extract metaphors, unusual word combinations, emotional valence
- Capture thematic connections between unrelated files
- Surface conceptual parallels (e.g., "the audio buffer ring pattern in relay/ mirrors the event queue in the chat module")
- Useful for Tresbuchet-style creative output where the goal is unexpected connections, not engineering precision

### Pattern Deviation Recognition (Reverse NZYM)
Use NZYM digests as a baseline to detect deviations:
- Compare a file/folder against its expected pattern (derived from the digest of similar folders)
- Flag inconsistencies: naming convention breaks, missing expected files, unusual import patterns
- Works on datasets too: establish the "shape" of a dataset via digest, then scan for rows/entries that deviate from the pattern
- Like a linter but for architectural patterns and data consistency

### Cross-Dimensional Pattern Matching
Find parallels across different idea spaces and codebases:
- Scan multiple `.enzyme` digests across repos
- Identify shared design patterns, similar architectures, reusable abstractions
- "relay/ uses the same pub/sub pattern as the WebSocket layer in bridge/"
- "the audio processing pipeline in snowglobe/ parallels the image processing in nextgenart/"
- During creation, the AI draws from the full pattern vocabulary of the creator's existing work

This would have been valuable developing WaveLoop — recognizing that existing patterns in relay/ and snowglobe/ could be composed rather than reinvented.

---

## Long-term / Research

### LLM-Powered Compression Insert
Replace the deterministic first-line + keywords extraction with an LLM call that produces a semantic summary per file. The FX-loop architecture already supports this — swap the tick function without changing the output contract. Trade compute cost for quality.

Options:
- **LLMLingua-style:** Use a small model (GPT-2 / LLaMA-7B) for token-level classification. 20x compression, 1.5% quality loss.
- **Function-level:** Parse AST, rank functions by structural importance (aider repo-map approach), keep only the most-referenced symbols.
- **Hybrid:** Deterministic for small files (already inlined), LLM for large files (where keyword extraction loses the most context).

### Staleness Detection
Track when source files change and mark `.enzyme` digests as stale. Options:
- Checksum-based: store content hash per file, regenerate on mismatch
- Git-hook-based: regenerate on commit
- Watch mode: `enzyme --watch` for continuous regeneration

### Multi-Format Output
Currently XML only. Add:
- Markdown (for pasting into Claude chats)
- JSON (for programmatic consumption)
- Plain text (for piping)

### Digest Composition
Compose multiple `.enzyme` files into a single meta-digest. Read 10 folder digests, produce 1 repo-level summary. Useful for the root-scope mode and cross-repo pattern matching.

---

## Philosophy

NZYM sits at the intersection of two ideas:

1. **Context is the bottleneck.** LLMs are powerful but context-window-limited. Every token that doesn't carry signal is waste — wasted energy, wasted water, wasted latency. NZYM front-loads understanding into pre-computed digests so the LLM spends tokens on thinking, not reading.

2. **Creators work in patterns.** A developer's repos aren't independent — they share design patterns, naming conventions, architectural instincts. NZYM's cross-dimensional vision is to make those patterns legible across the entire creative output, so the AI assistant works WITH the creator's vocabulary rather than inventing a new one each session.

The strict/delulu spectrum captures the tension between these: strict mode serves engineering precision (follow the pattern exactly), delulu mode serves creative discovery (find patterns you didn't know you had).

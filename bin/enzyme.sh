#!/usr/bin/env bash
# nzym — auto-generated LLM-optimized folder digests
# Usage: enzyme [options] <path> [path2 ...]
#   enzyme ./src               → generate .enzyme for ./src
#   enzyme ./src ./docs        → generate for both
#   enzyme --config .enzyme.yml ./src  → use custom config
#   enzyme --inline 80         → inline files under 80 lines
#   enzyme --output digest.xml → custom output filename
set -euo pipefail

VERSION="0.1.0"
INLINE_THRESHOLD=50
OUTPUT_FILE=".enzyme"
FORMAT="xml"
CONFIG_FILE=""

# ── Parse args ───────────────────────────────────────────────
usage() {
  echo "nzym v${VERSION} — LLM-optimized folder digests"
  echo ""
  echo "Usage: enzyme [options] <path> [path2 ...]"
  echo ""
  echo "Options:"
  echo "  --config <file>   Config file (default: .enzyme.yml in target or repo root)"
  echo "  --inline <lines>  Inline files under N lines (default: ${INLINE_THRESHOLD})"
  echo "  --output <file>   Output filename (default: ${OUTPUT_FILE})"
  echo "  --version         Print version"
  echo "  --help            This message"
  exit 0
}

TARGETS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)  CONFIG_FILE="$2"; shift 2 ;;
    --inline)  INLINE_THRESHOLD="$2"; shift 2 ;;
    --output)  OUTPUT_FILE="$2"; shift 2 ;;
    --version) echo "nzym v${VERSION}"; exit 0 ;;
    --help|-h) usage ;;
    -*)        echo "Unknown option: $1"; exit 1 ;;
    *)         TARGETS+=("$1"); shift ;;
  esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "Error: no target path(s) specified"
  echo "Usage: nzym <path> [path2 ...]"
  exit 1
fi

# ── Config loading (basic YAML parsing) ─────────────────────
load_config() {
  local dir="$1"
  local cfg=""

  # Priority: --config flag > dir/.enzyme.yml > repo root .enzyme.yml
  if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    cfg="$CONFIG_FILE"
  elif [[ -f "${dir}/.enzyme.yml" ]]; then
    cfg="${dir}/.enzyme.yml"
  elif [[ -f ".enzyme.yml" ]]; then
    cfg=".enzyme.yml"
  fi

  if [[ -n "$cfg" ]]; then
    # Extract simple values (bash YAML "parsing" — good enough for flat keys)
    local val
    val=$(grep -E '^\s*inline_below_lines:' "$cfg" 2>/dev/null | head -1 | sed 's/.*: *//' | tr -d '"')
    [[ -n "$val" ]] && INLINE_THRESHOLD="$val"
    val=$(grep -E '^\s*output_file:' "$cfg" 2>/dev/null | head -1 | sed 's/.*: *//' | tr -d '"')
    [[ -n "$val" ]] && OUTPUT_FILE="$val"
    val=$(grep -E '^\s*format:' "$cfg" 2>/dev/null | head -1 | sed 's/.*: *//' | tr -d '"')
    [[ -n "$val" ]] && FORMAT="$val"
  fi
}

# ── Stop words for keyword extraction ────────────────────────
STOP_WORDS="the a an and or but in on at to for of is it that this with from by as are was be have has had do does did will would could should may might can shall not no its"

# ── Extract keywords from text ───────────────────────────────
extract_keywords() {
  local text="$1"
  local count="${2:-8}"

  echo "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alpha:]' '\n' \
    | awk -v stops="$STOP_WORDS" '
      BEGIN { split(stops, s, " "); for (i in s) stop[s[i]]=1 }
      length >= 3 && !stop[$0] { freq[$0]++ }
      END { for (w in freq) print freq[w], w }
    ' \
    | sort -rn \
    | head -"$count" \
    | awk '{print $2}' \
    | paste -sd ',' -
}

# ── Extract first meaningful line ────────────────────────────
first_line() {
  local file="$1"
  # Skip blank lines, headings (#), frontmatter (---), HTML comments
  grep -vE '^\s*$|^#|^---|^<!--|^-->|^```' "$file" 2>/dev/null \
    | head -1 \
    | sed 's/^> //' \
    | cut -c1-200
}

# ── XML-escape ───────────────────────────────────────────────
xml_escape() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

# ── Process a single folder ──────────────────────────────────
process_folder() {
  local dir="$1"
  dir="${dir%/}"  # strip trailing slash

  if [[ ! -d "$dir" ]]; then
    echo "Warning: ${dir} is not a directory, skipping" >&2
    return
  fi

  load_config "$dir"

  local total_files=0
  local total_bytes=0
  local total_lines=0
  local entries=""
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Collect files (non-hidden, non-binary, skip .enzyme itself)
  local files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$dir" -maxdepth 1 -type f -not -name '.*' -not -name "$OUTPUT_FILE" -print0 2>/dev/null | sort -z)

  # Skip empty folders
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "nzym: ${dir}/ → (empty, skipped)" >&2
    return
  fi

  for filepath in "${files[@]}"; do
    local fname
    fname=$(basename "$filepath")

    # Skip binary files
    if file -b --mime-type "$filepath" 2>/dev/null | grep -qvE '^text/'; then
      continue
    fi

    local lines bytes modified summary
    lines=$(wc -l < "$filepath" | tr -d ' ')
    bytes=$(wc -c < "$filepath" | tr -d ' ')
    modified=$(stat -f '%Sm' -t '%Y-%m-%d' "$filepath" 2>/dev/null || stat -c '%y' "$filepath" 2>/dev/null | cut -d' ' -f1)

    total_files=$((total_files + 1))
    total_bytes=$((total_bytes + bytes))
    total_lines=$((total_lines + lines))

    if [[ "$lines" -le "$INLINE_THRESHOLD" ]]; then
      # Small file: inline full content
      local content
      content=$(cat "$filepath" | xml_escape)
      entries="${entries}<file name=\"${fname}\" lines=\"${lines}\" bytes=\"${bytes}\" modified=\"${modified}\" mode=\"inline\">
${content}
</file>
"
    else
      # Large file: deterministic summary
      local fl kw
      fl=$(first_line "$filepath" | xml_escape)
      kw=$(extract_keywords "$(cat "$filepath")" 8)

      if [[ -n "$fl" ]]; then
        summary="${fl}"
      else
        summary="[no extractable summary]"
      fi

      entries="${entries}<file name=\"${fname}\" lines=\"${lines}\" bytes=\"${bytes}\" modified=\"${modified}\" keywords=\"${kw}\">
${summary}
</file>
"
    fi
  done

  # Write digest
  local outpath="${dir}/${OUTPUT_FILE}"
  local folder_name
  folder_name=$(basename "$dir")

  cat > "$outpath" <<DIGEST
<enzyme folder="${folder_name}" files="${total_files}" bytes="${total_bytes}" lines="${total_lines}" generated="${now}" mode="deterministic" version="${VERSION}">
${entries}</enzyme>
DIGEST

  # Stats
  local digest_bytes
  digest_bytes=$(wc -c < "$outpath" | tr -d ' ')
  local ratio=0
  if [[ "$total_bytes" -gt 0 ]]; then
    ratio=$(( (total_bytes - digest_bytes) * 100 / total_bytes ))
  fi

  # Skip if XML overhead causes massive expansion (>50% bigger than raw).
  # Small expansion is acceptable — digest value is read-count reduction (1 read vs N reads),
  # not just byte reduction.
  if [[ "$ratio" -lt -50 ]]; then
    rm -f "$outpath"
    echo "nzym: ${dir}/ → skipped (${total_files} files, ${total_bytes} bytes — XML overhead too large)" >&2
    return
  fi

  echo "nzym: ${dir}/ → ${OUTPUT_FILE} (${total_files} files, ${total_bytes}→${digest_bytes} bytes, ${ratio}% compression)"
}

# ── Main ─────────────────────────────────────────────────────
for target in "${TARGETS[@]}"; do
  process_folder "$target"
done

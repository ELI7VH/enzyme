#!/usr/bin/env bash
# nzym — auto-generated LLM-optimized folder digests
# Usage: enzyme [options] <path> [path2 ...]
#   enzyme ./src               → generate .enzyme for ./src
#   enzyme ./src ./docs        → generate for both
#   enzyme -r ./src            → recursive (all subdirs, bottom-up)
#   enzyme --config .enzyme.yml ./src  → use custom config
#   enzyme --inline 80         → inline files under 80 lines
#   enzyme --output digest.xml → custom output filename
set -euo pipefail

VERSION="0.2.0"
INLINE_THRESHOLD=50
OUTPUT_FILE=".enzyme"
FORMAT="xml"
CONFIG_FILE=""
RECURSIVE=false

# ── Fallback directory ignore patterns (used outside git repos) ──
FALLBACK_DIR_IGNORE="node_modules .git .hg .svn __pycache__ .tox .mypy_cache .pytest_cache
dist build target out .next .nuxt .cache .parcel-cache .turbo
.godot .import vendor deps _build .elixir_ls .zig-cache
_deps CMakeFiles .vs .vscode .idea coverage .nyc_output .gradle
.eggs DerivedData Pods"

# ── Parse args ───────────────────────────────────────────────
usage() {
  echo "nzym v${VERSION} — LLM-optimized folder digests"
  echo ""
  echo "Usage: enzyme [options] <path> [path2 ...]"
  echo ""
  echo "Options:"
  echo "  -r, --recursive   Walk subdirectories bottom-up, roll up child digests"
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
    -r|--recursive) RECURSIVE=true; shift ;;
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

# ── Detect if a path is inside a git repo ─────────────────────
is_in_git_repo() {
  local dir="$1"
  git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null
}

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

# ── Extract keywords from text (reads from stdin) ────────────
extract_keywords() {
  local count="${1:-8}"

  tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alpha:]' '\n' \
    | awk -v stops="$STOP_WORDS" '
      BEGIN { split(stops, s, " "); for (i in s) stop[s[i]]=1 }
      length >= 3 && !stop[$0] { freq[$0]++ }
      END { for (w in freq) print freq[w], w }
    ' \
    | sort -rn \
    | awk -v n="$count" 'NR<=n {print $2}' \
    | paste -sd ',' -
}

# ── Extract first meaningful line ────────────────────────────
first_line() {
  local file="$1"
  # Skip blank lines, headings (#), frontmatter (---), HTML comments
  # Use awk instead of grep|head to avoid SIGPIPE on large files
  awk '!/^\s*$/ && !/^#/ && !/^---/ && !/^<!--/ && !/^-->/ && !/^```/ { print; exit }' "$file" 2>/dev/null \
    | sed 's/^> //' \
    | cut -c1-200
}

# ── XML-escape ───────────────────────────────────────────────
xml_escape() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

# ── Portable file modification date ──────────────────────────
file_modified() {
  local filepath="$1"
  # GNU stat (Linux, Git Bash, MSYS) — try first since macOS stat -c fails cleanly
  local mod
  mod=$(stat -c '%y' "$filepath" 2>/dev/null | cut -d' ' -f1)
  if [[ -n "$mod" && "$mod" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "$mod"
    return
  fi
  # macOS stat
  mod=$(stat -f '%Sm' -t '%Y-%m-%d' "$filepath" 2>/dev/null)
  if [[ -n "$mod" && "$mod" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "$mod"
    return
  fi
  echo "unknown"
}

# ── Load .enzymeignore patterns ────────────────────────────────
load_ignore_patterns() {
  local dir="$1"
  IGNORE_PATTERNS=()

  # Default security patterns (always ignored)
  IGNORE_PATTERNS+=("*.env" ".env.*" "*.pem" "*.key" "*.p12" "*.pfx")
  IGNORE_PATTERNS+=("*secret*" "*credential*" "*password*" "*token*")
  IGNORE_PATTERNS+=("id_rsa*" "id_ed25519*" "*.keystore")

  # Load .enzymeignore from dir, then repo root
  local ignore_file=""
  if [[ -f "${dir}/.enzymeignore" ]]; then
    ignore_file="${dir}/.enzymeignore"
  elif [[ -f ".enzymeignore" ]]; then
    ignore_file=".enzymeignore"
  fi

  if [[ -n "$ignore_file" ]]; then
    while IFS= read -r pattern; do
      # Skip comments and blank lines
      [[ "$pattern" =~ ^#.*$ || -z "$pattern" ]] && continue
      IGNORE_PATTERNS+=("$pattern")
    done < "$ignore_file"
  fi
}

# ── Check if a filename matches ignore patterns ───────────────
is_ignored() {
  local fname="$1"
  local lname
  lname=$(echo "$fname" | tr '[:upper:]' '[:lower:]')
  for pattern in "${IGNORE_PATTERNS[@]}"; do
    # shellcheck disable=SC2254
    case "$lname" in
      $pattern) return 0 ;;
    esac
  done
  return 1
}

# ── Check if a directory should be skipped (fallback) ─────────
is_dir_ignored_fallback() {
  local dname="$1"
  local ign
  for ign in $FALLBACK_DIR_IGNORE; do
    [[ "$dname" == "$ign" ]] && return 0
  done
  # Also skip hidden dirs
  [[ "$dname" == .* ]] && return 0
  return 1
}

# ── Extract summary from a child .enzyme file ─────────────────
# Reads a child's .enzyme and produces a <subfolder> XML element
summarize_child_digest() {
  local child_enzyme="$1"
  local child_name="$2"

  if [[ ! -f "$child_enzyme" ]]; then
    return
  fi

  # Extract attributes from the root <enzyme> tag
  local files_attr bytes_attr lines_attr
  files_attr=$(grep -o 'files="[^"]*"' "$child_enzyme" | head -1 | sed 's/files="//;s/"//')
  bytes_attr=$(grep -o 'bytes="[^"]*"' "$child_enzyme" | head -1 | sed 's/bytes="//;s/"//')
  lines_attr=$(grep -o 'lines="[^"]*"' "$child_enzyme" | head -1 | sed 's/lines="//;s/"//')

  # Count subfolder elements in child (for total_subfolders)
  local child_subfolders
  child_subfolders=$(grep -c '<subfolder ' "$child_enzyme" 2>/dev/null) || true
  [[ -z "$child_subfolders" ]] && child_subfolders=0

  # Extract all keywords from child digest (from file keyword attrs + subfolder keyword attrs)
  local all_keywords
  all_keywords=$(grep -o 'keywords="[^"]*"' "$child_enzyme" 2>/dev/null \
    | sed 's/keywords="//;s/"//' \
    | tr ',' '\n' \
    | sort | uniq -c | sort -rn \
    | awk 'NR<=8 {print $2}' \
    | paste -sd ',' -)

  # Extract file names from child digest for a content listing
  local file_names
  file_names=$(grep -o '<file name="[^"]*"' "$child_enzyme" 2>/dev/null \
    | sed 's/<file name="//;s/"//' \
    | paste -sd ',' -)

  # Collect subfolder names from child (for nested tree awareness)
  local subfolder_names
  subfolder_names=$(grep -o '<subfolder name="[^"]*"' "$child_enzyme" 2>/dev/null \
    | sed 's/<subfolder name="//;s/"//' \
    | paste -sd ',' -)

  # Build the summary text: file listing + nested subfolders
  local summary_text=""
  if [[ -n "$file_names" ]]; then
    summary_text="files: ${file_names}"
  fi
  if [[ -n "$subfolder_names" ]]; then
    [[ -n "$summary_text" ]] && summary_text="${summary_text} | "
    summary_text="${summary_text}subfolders: ${subfolder_names}"
  fi

  # Emit <subfolder> element
  local attrs="name=\"${child_name}\""
  [[ -n "$files_attr" ]] && attrs="${attrs} files=\"${files_attr}\""
  [[ -n "$lines_attr" ]] && attrs="${attrs} lines=\"${lines_attr}\""
  [[ -n "$bytes_attr" ]] && attrs="${attrs} bytes=\"${bytes_attr}\""
  [[ -n "$child_subfolders" && "$child_subfolders" != "0" ]] && attrs="${attrs} subfolders=\"${child_subfolders}\""
  [[ -n "$all_keywords" ]] && attrs="${attrs} keywords=\"${all_keywords}\""
  attrs="${attrs} digest=\"true\""

  echo "<subfolder ${attrs}>"
  if [[ -n "$summary_text" ]]; then
    echo "${summary_text}"
  fi
  echo "</subfolder>"
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
  load_ignore_patterns "$dir"

  local total_files=0
  local total_bytes=0
  local total_lines=0
  local entries=""
  local subfolder_entries=""
  local subfolder_count=0
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Collect files (non-hidden, non-binary, skip .enzyme itself)
  local files=()
  while IFS= read -r -d '' f; do
    local bname
    bname=$(basename "$f")
    # Skip files matching .enzymeignore patterns
    if is_ignored "$bname"; then
      continue
    fi
    files+=("$f")
  done < <(find "$dir" -maxdepth 1 -type f -not -name '.*' -not -name "$OUTPUT_FILE" -print0 2>/dev/null | sort -z)

  # Collect subfolder digests (roll up child .enzyme files into parent)
  local subdirs=()
  while IFS= read -r -d '' sd; do
    local sdname
    sdname=$(basename "$sd")
    # Skip ignored directories (git-aware or fallback)
    if is_in_git_repo "$dir"; then
      git -C "$dir" check-ignore -q "$sd" 2>/dev/null && continue
    else
      is_dir_ignored_fallback "$sdname" && continue
    fi
    subdirs+=("$sd")
  done < <(find "$dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)

  for subdir in "${subdirs[@]}"; do
    local sdname child_enzyme
    sdname=$(basename "$subdir")
    child_enzyme="${subdir}/${OUTPUT_FILE}"
    if [[ -f "$child_enzyme" ]]; then
      local child_summary
      child_summary=$(summarize_child_digest "$child_enzyme" "$sdname")
      if [[ -n "$child_summary" ]]; then
        subfolder_entries="${subfolder_entries}${child_summary}
"
        subfolder_count=$((subfolder_count + 1))
      fi
    fi
  done

  # Skip if no files AND no subfolder digests
  if [[ ${#files[@]} -eq 0 && $subfolder_count -eq 0 ]]; then
    echo "nzym: ${dir}/ → (empty, skipped)" >&2
    return
  fi

  for filepath in "${files[@]}"; do
    local fname
    fname=$(basename "$filepath")

    # Skip binary files (allow text/* and common text-based application/* types)
    local mime
    mime=$(file -b --mime-type "$filepath" 2>/dev/null || echo "unknown")
    if [[ "$mime" != text/* && "$mime" != application/json && "$mime" != application/javascript \
       && "$mime" != application/xml && "$mime" != application/x-yaml \
       && "$mime" != application/toml && "$mime" != application/x-shellscript \
       && "$mime" != application/x-ruby && "$mime" != application/x-perl \
       && "$mime" != application/x-ndjson ]]; then
      continue
    fi

    local lines bytes modified summary
    lines=$(wc -l < "$filepath" | tr -d ' ')
    bytes=$(wc -c < "$filepath" | tr -d ' ')
    modified=$(file_modified "$filepath")

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
      kw=$(cat "$filepath" | extract_keywords 8)

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

  # Build root tag attributes
  local root_attrs="folder=\"${folder_name}\" files=\"${total_files}\" bytes=\"${total_bytes}\" lines=\"${total_lines}\""
  if [[ $subfolder_count -gt 0 ]]; then
    root_attrs="${root_attrs} subfolders=\"${subfolder_count}\""
  fi
  root_attrs="${root_attrs} generated=\"${now}\" mode=\"deterministic\" version=\"${VERSION}\""

  cat > "$outpath" <<DIGEST
<enzyme ${root_attrs}>
${entries}${subfolder_entries}</enzyme>
DIGEST

  # Stats
  local digest_bytes
  digest_bytes=$(wc -c < "$outpath" | tr -d ' ')
  local ratio=0
  if [[ "$total_bytes" -gt 0 ]]; then
    ratio=$(( (total_bytes - digest_bytes) * 100 / total_bytes ))
  fi

  # Skip if XML overhead causes massive expansion (>50% bigger than raw).
  # But never skip folders that have subfolder digests — their value is the tree map.
  if [[ "$ratio" -lt -50 && $subfolder_count -eq 0 ]]; then
    rm -f "$outpath"
    echo "nzym: ${dir}/ → skipped (${total_files} files, ${total_bytes} bytes — XML overhead too large)" >&2
    return
  fi

  local extra=""
  [[ $subfolder_count -gt 0 ]] && extra=", ${subfolder_count} subfolders"
  echo "nzym: ${dir}/ → ${OUTPUT_FILE} (${total_files} files, ${total_bytes}→${digest_bytes} bytes, ${ratio}% compression${extra})"
}

# ── Recursive walk (bottom-up) ───────────────────────────────
process_recursive() {
  local root="$1"
  root="${root%/}"

  if [[ ! -d "$root" ]]; then
    echo "Warning: ${root} is not a directory, skipping" >&2
    return
  fi

  # Collect directories, sort by depth descending (bottom-up)
  # This ensures children are processed before parents so roll-up works
  local dirs=()
  local target_in_git=false
  is_in_git_repo "$root" && target_in_git=true

  if [[ "$target_in_git" == true ]]; then
    # Use git ls-files to discover directories — avoids walking gitignored trees entirely
    # This is O(tracked files) not O(all files including node_modules/build dirs)
    declare -A seen_dirs
    while IFS= read -r d; do
      [[ -z "$d" || -n "${seen_dirs[$d]+x}" ]] && continue
      [[ -d "$d" ]] && { seen_dirs["$d"]=1; dirs+=("$d"); }
      # Also add all parent directories up to root
      local parent="$d"
      while [[ "$parent" == */* ]]; do
        parent="${parent%/*}"
        [[ "$parent" == "$root" || -z "$parent" ]] && break
        [[ -n "${seen_dirs[$parent]+x}" ]] && break
        [[ -d "$parent" ]] && { seen_dirs["$parent"]=1; dirs+=("$parent"); }
      done
    done < <(
      (git ls-files "$root" 2>/dev/null; git ls-files --others --exclude-standard "$root" 2>/dev/null) \
        | sed 's|/[^/]*$||' | sort -u
    )
    # Add root itself
    if [[ -z "${seen_dirs[$root]+x}" ]]; then
      dirs+=("$root")
    fi
    # Re-sort by depth descending (bottom-up)
    local sorted_dirs=()
    while IFS= read -r d; do
      [[ -n "$d" ]] && sorted_dirs+=("$d")
    done < <(printf '%s\n' "${dirs[@]}" | awk -F/ '{print NF, $0}' | sort -rn | cut -d' ' -f2-)
    dirs=("${sorted_dirs[@]}")
  else
    # No git — find + fallback ignore list
    while IFS= read -r d; do
      local skip=false
      local rel="${d#${root}}"
      rel="${rel#/}"
      if [[ -n "$rel" ]]; then
        IFS='/' read -ra parts <<< "$rel"
        for part in "${parts[@]}"; do
          if is_dir_ignored_fallback "$part"; then
            skip=true
            break
          fi
        done
      fi
      [[ "$skip" == true ]] && continue
      dirs+=("$d")
    done < <(find "$root" -type d 2>/dev/null | awk -F/ '{print NF, $0}' | sort -rn | cut -d' ' -f2-)
  fi

  local processed=0
  for d in "${dirs[@]}"; do
    process_folder "$d"
    processed=$((processed + 1))
  done

  echo "nzym: recursive complete — ${processed} directories processed"
}

# ── Main ─────────────────────────────────────────────────────
for target in "${TARGETS[@]}"; do
  if [[ "$RECURSIVE" == true ]]; then
    process_recursive "$target"
  else
    process_folder "$target"
  fi
done

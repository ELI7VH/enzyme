#!/usr/bin/env bash
# NZYM Benchmark — Run enzyme across all repos + Obsidian vaults
# Usage: benchmark-all.sh [repos-root]
set -euo pipefail

ENZYME_BIN="$(cd "$(dirname "$0")" && pwd)/enzyme.sh"
REPOS_ROOT="${1:-/c/Users/elija/repos}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULTS_FILE="${SCRIPT_DIR}/benchmark-results-${TIMESTAMP}.csv"
SUMMARY_FILE="${SCRIPT_DIR}/benchmark-summary.txt"
LOG_FILE="${SCRIPT_DIR}/benchmark-${TIMESTAMP}.log"

echo "repo,folder,files,raw_bytes,digest_bytes,compression_pct,elapsed_ms" > "$RESULTS_FILE"

TOTAL_FOLDERS=0
TOTAL_FILES=0
TOTAL_RAW=0
TOTAL_DIGEST=0
TOTAL_SKIPPED=0
TOTAL_ERRORS=0
START_TIME=$(date +%s)

log() {
  echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE" >&2
}

parse_enzyme_output() {
  local line="$1"
  PARSED_FILES=$(echo "$line" | sed -n 's/.*(\([0-9]*\) files.*/\1/p')
  PARSED_RAW=$(echo "$line" | sed -n 's/.* \([0-9]*\)→.*/\1/p')
  PARSED_DIGEST=$(echo "$line" | sed -n 's/.*→\([0-9]*\) bytes.*/\1/p')
  PARSED_PCT=$(echo "$line" | sed -n 's/.*[, ]\(-\{0,1\}[0-9]*\)% compression.*/\1/p')
}

# Process a single folder
run_folder() {
  local folder="$1"
  local label="$2"
  local idx="$3"
  local total="$4"

  local pct_done=$((idx * 100 / total))

  t0=$(date +%s%N 2>/dev/null || date +%s)
  output=$(timeout 15 bash "$ENZYME_BIN" "$folder" 2>&1) || {
    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
    log "[${idx}/${total}] (${pct_done}%) ERROR: ${label}"
    return
  }
  t1=$(date +%s%N 2>/dev/null || date +%s)

  if echo "$output" | grep -q "skipped\|empty"; then
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
    return
  fi

  parse_enzyme_output "$output"

  if [[ -n "$PARSED_FILES" && "$PARSED_FILES" -gt 0 ]] 2>/dev/null; then
    elapsed_ms=0
    if [[ ${#t0} -gt 10 && ${#t1} -gt 10 ]]; then
      elapsed_ms=$(( (t1 - t0) / 1000000 ))
    fi

    echo "${label%%/*},${label},${PARSED_FILES},${PARSED_RAW},${PARSED_DIGEST},${PARSED_PCT},${elapsed_ms}" >> "$RESULTS_FILE"

    TOTAL_FOLDERS=$((TOTAL_FOLDERS + 1))
    TOTAL_FILES=$((TOTAL_FILES + PARSED_FILES))
    TOTAL_RAW=$((TOTAL_RAW + PARSED_RAW))
    TOTAL_DIGEST=$((TOTAL_DIGEST + PARSED_DIGEST))

    log "[${idx}/${total}] (${pct_done}%) ${PARSED_PCT}%: ${label} (${PARSED_FILES}f, ${elapsed_ms}ms)"
  fi
}

# Process a root directory: find folders up to depth 4, pruning junk
process_root() {
  local root="$1"
  local prefix="$2"
  local folders_file="$3"

  find "$root" -maxdepth 4 -type d \
    \( -name node_modules -o -name .git -o -name vendor -o -name dist \
       -o -name .next -o -name build -o -name __pycache__ -o -name target \
       -o -name .cache -o -name .venv -o -name venv -o -name .obsidian \
       -o -name .cargo -o -name .rustup -o -name coverage -o -name .nyc_output \
       -o -name .parcel-cache -o -name .turbo -o -name locales -o -name fonts \
       -o -name '.*' \) -prune \
    -o -type d -print 2>/dev/null | while IFS= read -r d; do
      echo "${prefix}|${d}"
    done >> "$folders_file"
}

log "NZYM Benchmark starting"
log "Repos: ${REPOS_ROOT}"

# Step 1: Collect all folders into a temp file (fast)
FOLDERS_FILE=$(mktemp)
log "Scanning folders..."

for repo in "$REPOS_ROOT"/*/; do
  [[ -d "$repo" ]] || continue
  rname=$(basename "$repo")
  process_root "$repo" "$rname" "$FOLDERS_FILE"
done

# Obsidian
OBSIDIAN_ROOT="/c/Users/elija/iCloudDrive/iCloud~md~obsidian"
if [[ -d "$OBSIDIAN_ROOT" ]]; then
  for vault in "$OBSIDIAN_ROOT"/*/; do
    [[ -d "$vault" ]] || continue
    vname="obsidian/$(basename "$vault")"
    process_root "$vault" "$vname" "$FOLDERS_FILE"
  done
fi

FOLDER_COUNT=$(wc -l < "$FOLDERS_FILE" | tr -d ' ')
log "Found ${FOLDER_COUNT} folders"
log "---"

# Step 2: Process each folder
IDX=0
while IFS='|' read -r label folder; do
  IDX=$((IDX + 1))
  run_folder "$folder" "$label" "$IDX" "$FOLDER_COUNT"
done < "$FOLDERS_FILE"

rm -f "$FOLDERS_FILE"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

OVERALL_PCT=0
if [[ "$TOTAL_RAW" -gt 0 ]]; then
  OVERALL_PCT=$(( (TOTAL_RAW - TOTAL_DIGEST) * 100 / TOTAL_RAW ))
fi

RAW_MB=$(awk "BEGIN{printf \"%.2f\", $TOTAL_RAW / 1048576}")
DIGEST_MB=$(awk "BEGIN{printf \"%.2f\", $TOTAL_DIGEST / 1048576}")
RAW_TOKENS=$((TOTAL_RAW / 4))
DIGEST_TOKENS=$((TOTAL_DIGEST / 4))
SAVED_TOKENS=$((RAW_TOKENS - DIGEST_TOKENS))

cat > "$SUMMARY_FILE" <<EOF
NZYM Benchmark Summary
======================================
Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Machine: $(hostname 2>/dev/null || echo "windows-gpu") (Windows 11, GPU workstation)
Repos: ${REPOS_ROOT}
Elapsed: ${ELAPSED}s

Folders processed: ${TOTAL_FOLDERS}
Folders skipped: ${TOTAL_SKIPPED}
Errors: ${TOTAL_ERRORS}
Files digested: ${TOTAL_FILES}

Raw: ${TOTAL_RAW} bytes (${RAW_MB} MB)
Digest: ${TOTAL_DIGEST} bytes (${DIGEST_MB} MB)
Compression: ${OVERALL_PCT}%

Tokens (raw): ${RAW_TOKENS}
Tokens (digest): ${DIGEST_TOKENS}
Tokens saved: ${SAVED_TOKENS} (${OVERALL_PCT}%)

CSV: ${RESULTS_FILE}
Log: ${LOG_FILE}
EOF

log "---"
log "DONE in ${ELAPSED}s"
cat "$SUMMARY_FILE"

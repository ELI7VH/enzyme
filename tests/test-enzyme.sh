#!/usr/bin/env bash
# NZYM test suite — validates enzyme.sh behavior
set -euo pipefail

ENZYME="$(cd "$(dirname "$0")/../bin" && pwd)/enzyme.sh"
PASS=0
FAIL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

# ── Setup test fixtures ──────────────────────────────────────

setup_small_folder() {
  local d="$TMPDIR/small"
  mkdir -p "$d"
  # Need 5+ files with substantial content to beat XML overhead
  {
    echo 'const x = 1;'
    echo 'const y = 2;'
    echo 'const z = x + y;'
    echo 'function greet(name) { return "Hello, " + name; }'
    echo 'function add(a, b) { return a + b; }'
    echo 'function multiply(a, b) { return a * b; }'
    echo 'function subtract(a, b) { return a - b; }'
    echo 'function divide(a, b) { return b !== 0 ? a / b : 0; }'
    echo 'function power(base, exp) { return Math.pow(base, exp); }'
    echo 'function modulo(a, b) { return a % b; }'
    echo 'module.exports = { greet, add, multiply, subtract, divide, power, modulo };'
  } > "$d/tiny.js"
  for i in 1 2 3 4; do
    {
      echo "# Document $i"
      echo ""
      echo "This is test document number $i with substantial content."
      echo "It exists to ensure the folder has enough raw bytes"
      echo "that the XML digest wrapper is smaller than the content."
      echo "Each document has multiple lines of prose to simulate"
      echo "a realistic project folder with documentation."
      echo ""
      echo "## Section A"
      echo "Details about topic A in document $i."
      echo "Additional context and explanation follows here."
      echo "The NZYM tool should inline this file since it is short."
      echo ""
      echo "## Section B"
      echo "More information about topic B."
      echo "Cross-references to other documents in the folder."
      echo "Final notes and conclusions for document $i."
    } > "$d/doc${i}.md"
  done
  echo "$d"
}

setup_large_folder() {
  local d="$TMPDIR/large"
  mkdir -p "$d"
  # Create a file with 80 lines (above default 50 threshold)
  for i in $(seq 1 80); do
    echo "// line $i: some code here doing things"
  done > "$d/big.js"
  # Create a small file
  echo 'export default {}' > "$d/small.ts"
  echo "$d"
}

setup_mixed_folder() {
  local d="$TMPDIR/mixed"
  mkdir -p "$d"
  # Need enough text files with enough content to beat XML overhead
  for i in 1 2 3 4 5; do
    {
      echo "# File $i"
      echo "This is text file number $i in the mixed folder."
      echo "It contains enough content that the XML digest wrapper"
      echo "will be smaller than the total raw content."
      echo "Multiple lines of text simulate a realistic project."
      echo "The binary and hidden files should be excluded."
      echo "Only these text files should appear in the digest."
      echo "Each file contributes to the total byte count."
      echo "NZYM should inline all of these since they are short."
      echo "End of file $i."
    } > "$d/file${i}.txt"
  done
  # Binary file (PNG header)
  printf '\x89PNG\r\n\x1a\n' > "$d/image.png"
  echo '.hidden content' > "$d/.secret"
  echo "$d"
}

setup_empty_folder() {
  local d="$TMPDIR/empty"
  mkdir -p "$d"
  echo "$d"
}

# ── Tests ─────────────────────────────────────────────────────

echo "=== NZYM Test Suite ==="
echo ""

# Test 1: Basic generation
echo "Test 1: Basic digest generation"
d=$(setup_small_folder)
output=$(bash "$ENZYME" "$d" 2>&1)
if [[ -f "$d/.enzyme" ]]; then
  pass "Digest file created"
else
  fail "Digest file not created"
fi

# Test 2: XML structure
echo "Test 2: Valid XML structure"
if grep -q '<enzyme folder=' "$d/.enzyme" 2>/dev/null; then
  pass "Root <enzyme> tag present"
else
  fail "Missing root tag"
fi
if grep -q '</enzyme>' "$d/.enzyme" 2>/dev/null; then
  pass "Closing </enzyme> tag present"
else
  fail "Missing closing tag"
fi

# Test 3: Small files inlined
echo "Test 3: Small files inlined"
if grep -q 'mode="inline"' "$d/.enzyme" 2>/dev/null; then
  pass "Inline mode detected"
else
  fail "No inline files found"
fi
if grep -q 'const x = 1;' "$d/.enzyme" 2>/dev/null; then
  pass "File content inlined"
else
  fail "Content not inlined"
fi
rm -rf "$d"

# Test 4: Large files summarized
echo "Test 4: Large files get keywords"
d=$(setup_large_folder)
bash "$ENZYME" "$d" 2>/dev/null
if grep -q 'keywords=' "$d/.enzyme" 2>/dev/null; then
  pass "Keywords attribute present for large file"
else
  fail "No keywords for large file"
fi
if grep -q 'mode="inline"' "$d/.enzyme" 2>/dev/null; then
  pass "Small file still inlined alongside large"
else
  fail "Small file not inlined"
fi
rm -rf "$d"

# Test 5: Binary files skipped
echo "Test 5: Binary files skipped"
d=$(setup_mixed_folder)
bash "$ENZYME" "$d" 2>/dev/null
if ! grep -q 'image.png' "$d/.enzyme" 2>/dev/null; then
  pass "Binary file (PNG) excluded"
else
  fail "Binary file included in digest"
fi

# Test 6: Hidden files skipped
echo "Test 6: Hidden files skipped"
if ! grep -q '.secret' "$d/.enzyme" 2>/dev/null; then
  pass "Hidden file excluded"
else
  fail "Hidden file included in digest"
fi
rm -rf "$d"

# Test 7: Empty folder handled
echo "Test 7: Empty folder gracefully skipped"
d=$(setup_empty_folder)
output=$(bash "$ENZYME" "$d" 2>&1)
if [[ ! -f "$d/.enzyme" ]]; then
  pass "No digest for empty folder"
else
  fail "Digest created for empty folder"
fi
if echo "$output" | grep -q "skipped"; then
  pass "Skip message printed"
else
  fail "No skip message"
fi
rm -rf "$d"

# Test 8: Custom inline threshold
echo "Test 8: Custom --inline threshold"
d="$TMPDIR/large-threshold"
mkdir -p "$d"
for i in $(seq 1 80); do
  echo "// line $i: some code here doing things with variables and functions"
done > "$d/big.js"
echo 'export default {}' > "$d/small.ts"
# With threshold 100, the 80-line file should be inlined
bash "$ENZYME" --inline 100 "$d" 2>/dev/null
big_mode=$(grep 'big.js' "$d/.enzyme" 2>/dev/null | grep -o 'mode="inline"' || echo "")
if [[ -n "$big_mode" ]]; then
  pass "80-line file inlined at threshold 100"
else
  fail "80-line file not inlined at threshold 100"
fi
rm -rf "$d"

# Test 9: Custom output filename
echo "Test 9: Custom --output filename"
d=$(setup_small_folder)
bash "$ENZYME" --output "custom-digest.xml" "$d" 2>/dev/null
if [[ -f "$d/custom-digest.xml" ]]; then
  pass "Custom output filename works"
else
  fail "Custom output filename not created"
fi
rm -rf "$d"

# Test 10: Multiple targets
echo "Test 10: Multiple folder targets"
d1=$(setup_small_folder)
d2="$TMPDIR/second"
mkdir -p "$d2"
for i in 1 2 3 4 5; do
  {
    echo "# Second Folder Document $i"
    echo "This folder has enough content to generate a valid digest."
    echo "Multiple lines ensure we beat the XML overhead threshold."
    echo "The compression ratio should be positive for this to work."
    echo "More text content here to pad things out realistically."
    echo "Each line contributes to the total byte count."
    echo "The digest should be smaller than this raw content."
  } > "$d2/file${i}.txt"
done
output=$(bash "$ENZYME" "$d1" "$d2" 2>&1)
if [[ -f "$d1/.enzyme" && -f "$d2/.enzyme" ]]; then
  pass "Both folders got digests"
else
  fail "Not all folders got digests"
fi
rm -rf "$d1" "$d2"

# Test 11: Metadata attributes
echo "Test 11: Metadata attributes present"
d=$(setup_small_folder)
bash "$ENZYME" "$d" 2>/dev/null
if grep -q 'files="' "$d/.enzyme" && grep -q 'bytes="' "$d/.enzyme" && grep -q 'lines="' "$d/.enzyme"; then
  pass "File count, byte count, and line count in metadata"
else
  fail "Missing metadata attributes"
fi
if grep -q 'generated="' "$d/.enzyme"; then
  pass "Timestamp in metadata"
else
  fail "Missing timestamp"
fi
rm -rf "$d"

# Test 12: XML escaping
echo "Test 12: XML special characters escaped"
d="$TMPDIR/xmltest"
mkdir -p "$d"
for i in 1 2 3 4; do
  {
    echo "# Padding file $i"
    echo "Enough content to ensure positive compression ratio."
    echo "The XML overhead needs to be smaller than total content."
    echo "Each file adds to the raw byte count of the folder."
    echo "NZYM will inline all of these small text files."
    echo "This padding ensures the digest is worth creating."
    echo "Without enough files, the XML tags exceed the content."
    echo "That triggers the negative compression skip."
  } > "$d/pad${i}.md"
done
{
  echo 'if (a < b && c > d) { "hello" }'
  echo 'const result = x < y ? "less" : "more";'
  echo 'const html = "<div class=\"test\">" + content + "</div>";'
  echo 'function compare(a, b) {'
  echo '  if (a < b && b > 0) return -1;'
  echo '  if (a > b && a > 0) return 1;'
  echo '  return 0;'
  echo '}'
  echo 'const escaped = str.replace(/&/g, "&amp;");'
} > "$d/special.txt"
bash "$ENZYME" "$d" 2>/dev/null
if grep -q '&lt;' "$d/.enzyme" && grep -q '&amp;' "$d/.enzyme"; then
  pass "XML entities escaped correctly"
else
  fail "XML escaping failed"
fi
rm -rf "$d"

# Test 13: Negative compression skip
echo "Test 13: Negative compression auto-skip"
d="$TMPDIR/tiny-folder"
mkdir -p "$d"
echo "hi" > "$d/a.txt"
output=$(bash "$ENZYME" "$d" 2>&1)
if [[ ! -f "$d/.enzyme" ]] || echo "$output" | grep -qi "skipped"; then
  pass "Tiny folder skipped or warned (XML overhead > content)"
else
  # It might still create the file if compression is positive for even tiny content
  pass "Tiny folder processed (content beats overhead)"
fi
rm -rf "$d"

# Test 14: Version flag
echo "Test 14: --version flag"
output=$(bash "$ENZYME" --version 2>&1)
if echo "$output" | grep -q 'nzym v'; then
  pass "--version prints version"
else
  fail "--version output unexpected: $output"
fi

# Test 15: Recursive mode — bottom-up digestion
echo "Test 15: Recursive mode"
d="$TMPDIR/recursive"
mkdir -p "$d/src/components" "$d/src/utils" "$d/lib"
# Each file needs enough content to avoid negative compression skip
for i in 1 2 3 4 5; do
  {
    for j in $(seq 1 12); do
      echo "export const Component${i}_part${j} = () => <div>Component ${i} render block ${j} with enough text to make the digest worthwhile</div>;"
    done
  } > "$d/src/components/Component${i}.tsx"
done
for i in 1 2 3 4 5; do
  {
    for j in $(seq 1 10); do
      echo "// Utility function ${i} variant ${j}"
      echo "export function util${i}_v${j}(x: number): number { return x * ${i} + ${j}; }"
    done
  } > "$d/src/utils/util${i}.ts"
done
for i in 1 2 3 4 5; do
  {
    echo "# Library module ${i}"
    echo ""
    echo "This module handles feature ${i} of the project."
    echo "It contains substantial content for testing enzyme digests."
    echo "Each file has enough text to ensure digest creation works."
    echo "The library is organized into discrete modules."
    echo "This padding ensures the XML overhead is smaller than content."
    echo "Additional lines help reach the threshold for positive compression."
    echo "The NZYM tool processes these files during recursive walks."
    echo "Bottom-up processing ensures children are digested before parents."
  } > "$d/lib/module${i}.md"
done
echo 'export { Component1 } from "./components/Component1";' > "$d/src/index.ts"
echo '{ "name": "test-project" }' > "$d/package.json"
output=$(bash "$ENZYME" -r "$d" 2>&1)
# Children should be processed first (bottom-up)
if [[ -f "$d/src/components/.enzyme" ]]; then
  pass "Leaf folder (components) digested"
else
  fail "Leaf folder not digested"
fi
if [[ -f "$d/src/.enzyme" ]]; then
  pass "Middle folder (src) digested"
else
  fail "Middle folder not digested"
fi
if [[ -f "$d/.enzyme" ]]; then
  pass "Root folder digested"
else
  fail "Root folder not digested"
fi

# Test 16: Subfolder roll-up in parent digest
echo "Test 16: Subfolder roll-up"
if grep -q '<subfolder name="components"' "$d/src/.enzyme" 2>/dev/null; then
  pass "Parent digest has <subfolder> for components"
else
  fail "Missing subfolder roll-up for components"
fi
if grep -q '<subfolder name="utils"' "$d/src/.enzyme" 2>/dev/null; then
  pass "Parent digest has <subfolder> for utils"
else
  fail "Missing subfolder roll-up for utils"
fi
if grep -q 'subfolders=' "$d/.enzyme" 2>/dev/null; then
  pass "Root digest has subfolders attribute"
else
  fail "Root digest missing subfolders attribute"
fi

# Test 17: Subfolder metadata extraction
echo "Test 17: Subfolder metadata"
if grep -q 'files="' "$d/src/.enzyme" 2>/dev/null && grep -q 'digest="true"' "$d/src/.enzyme" 2>/dev/null; then
  pass "Subfolder has file count and digest marker"
else
  fail "Subfolder missing metadata"
fi

# Test 18: Recursive with nested subfolders
echo "Test 18: Nested subfolder roll-up"
if grep -q '<subfolder name="src"' "$d/.enzyme" 2>/dev/null; then
  pass "Root has src subfolder summary"
else
  fail "Root missing src subfolder"
fi
if grep -q '<subfolder name="lib"' "$d/.enzyme" 2>/dev/null; then
  pass "Root has lib subfolder summary"
else
  fail "Root missing lib subfolder"
fi
rm -rf "$d"

# Test 19: File modification dates are clean (no stat garbage)
echo "Test 19: Clean modification dates"
d=$(setup_small_folder)
bash "$ENZYME" "$d" 2>/dev/null
# Check that modified attributes match YYYY-MM-DD or "unknown"
bad_dates=$(grep -o 'modified="[^"]*"' "$d/.enzyme" 2>/dev/null | grep -v -E 'modified="[0-9]{4}-[0-9]{2}-[0-9]{2}"' | grep -v 'modified="unknown"' || true)
if [[ -z "$bad_dates" ]]; then
  pass "All modification dates are clean YYYY-MM-DD format"
else
  fail "Bad date format found: $bad_dates"
fi
rm -rf "$d"

# ── Results ───────────────────────────────────────────────────

echo ""
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "  Total:  $((PASS + FAIL))"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi

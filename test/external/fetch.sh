#!/usr/bin/env bash
# fetch.sh — Download external CSS test suite resources.
#
# Idempotent: skips downloads if the correct commit marker exists.
# Run from repo root: test/external/fetch.sh
#
# Requires: git, python3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.json"

# ── Helpers ──────────────────────────────────────────────────────────

die() { echo "error: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# Extract a string value from the manifest JSON.
# Usage: json_str '.wpt.commit'
json_str() {
  python3 -c "
import json
with open('$MANIFEST') as f:
    d = json.load(f)
keys = '$1'.strip('.').split('.')
v = d
for k in keys:
    v = v[k]
print(v)
"
}

# Extract a JSON array of strings as newline-separated values.
json_arr() {
  python3 -c "
import json
with open('$MANIFEST') as f:
    d = json.load(f)
keys = '$1'.strip('.').split('.')
v = d
for k in keys:
    v = v[k]
for item in v:
    print(item)
"
}

# ── WPT reftests ─────────────────────────────────────────────────────

fetch_wpt() {
  local dest="$SCRIPT_DIR/wpt"
  local commit
  commit="$(json_str .wpt.commit)"
  local repo
  repo="$(json_str .wpt.repo)"
  local marker="$dest/.commit"

  if [ -f "$marker" ] && [ "$(cat "$marker")" = "$commit" ]; then
    echo "wpt: already at $commit, skipping"
    return
  fi

  echo "wpt: fetching commit $commit ..."
  rm -rf "$dest"
  mkdir -p "$dest"

  cd "$dest"
  git init -q
  git remote add origin "$repo"
  git config core.sparseCheckout true

  # Write sparse-checkout patterns: test files + support dirs
  local sparse_file="$dest/.git/info/sparse-checkout"
  json_arr .wpt.paths > "$sparse_file"
  json_arr .wpt.support_paths >> "$sparse_file"

  # Also include ref files adjacent to test files (same directory)
  json_arr .wpt.paths | while read -r path; do
    dirname "$path"
  done | sort -u >> "$sparse_file"

  git fetch --depth 1 origin "$commit" -q
  git checkout FETCH_HEAD -q

  echo "$commit" > "$marker"
  local count
  count=$(find . -name '*.html' -o -name '*.xhtml' -o -name '*.xht' | wc -l)
  echo "wpt: done ($count HTML files)"
  cd "$SCRIPT_DIR"
}

# ── Main ─────────────────────────────────────────────────────────────

need_cmd git
need_cmd python3

echo "=== Fetching external test resources ==="
fetch_wpt
echo "=== Done ==="
echo ""
echo "Note: Acid3 and Zen Garden tests use live URLs (no download needed)."
echo "      ARIA APG tests use a self-contained fixture (no download needed)."

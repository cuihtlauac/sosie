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
  local results_dir="$SCRIPT_DIR/wpt-results"

  # Sparse-checkout patterns from groups + support paths. The marker records
  # commit + patterns so that a groups/support change re-syncs the working
  # tree without refetching (the shallow clone already has all blobs) and
  # WITHOUT clearing the result cache (results are keyed by test path and
  # stay valid when the checkout only widens).
  local patterns
  patterns="$(
    json_arr .wpt.groups | while read -r group; do echo "$group/"; done
    json_arr .wpt.support_paths
  )"
  local want_marker="$commit
$patterns"

  if [ -f "$marker" ] && [ "$(cat "$marker")" = "$want_marker" ]; then
    echo "wpt: already at $commit with current sparse patterns, skipping"
    return
  fi

  local sparse_file="$dest/.git/info/sparse-checkout"

  if [ -f "$marker" ] && [ "$(head -n 1 "$marker")" = "$commit" ]; then
    echo "wpt: same commit, re-syncing sparse checkout ..."
    printf '%s\n' "$patterns" > "$sparse_file"
    git -C "$dest" read-tree -mu HEAD
    printf '%s\n' "$want_marker" > "$marker"
    local count
    count=$(find "$dest" -name '*.html' -o -name '*.xhtml' -o -name '*.xht' | wc -l)
    echo "wpt: done ($count HTML files)"
    return
  fi

  # New commit — invalidate cached results
  if [ -d "$results_dir" ]; then
    echo "wpt: clearing stale result cache"
    rm -rf "$results_dir"
  fi

  echo "wpt: fetching commit $commit ..."
  rm -rf "$dest"
  mkdir -p "$dest"

  cd "$dest"
  git init -q
  git remote add origin "$repo"
  git config core.sparseCheckout true

  mkdir -p "$(dirname "$sparse_file")"
  printf '%s\n' "$patterns" > "$sparse_file"

  git fetch --depth 1 origin "$commit" -q
  git checkout FETCH_HEAD -q

  printf '%s\n' "$want_marker" > "$marker"
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

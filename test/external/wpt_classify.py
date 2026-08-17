#!/usr/bin/env python3
"""WPT reftest classification database.

Builds a SQLite database from WPT test HTML metadata, cached test results,
and expectations.json. Supports querying, tagging, and exporting to a
durable JSON format.

Usage:
    wpt_classify.py bootstrap    # Build DB from sources
    wpt_classify.py export       # Export DB to classification.json
    wpt_classify.py import       # Import classification.json into DB
    wpt_classify.py summary      # Print classification summary
    wpt_classify.py query SQL    # Run arbitrary SQL
    wpt_classify.py tag PATH TAG # Add a tag to a test
    wpt_classify.py note PATH TXT # Add a note to a test
    wpt_classify.py sync-expectations  # Update expectations.json reasons
"""

import argparse
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DB_PATH = SCRIPT_DIR / "classification.db"
CLASSIFICATION_JSON = SCRIPT_DIR / "classification.json"
EXPECTATIONS_JSON = SCRIPT_DIR / "expectations.json"
WPT_DIR = SCRIPT_DIR / "wpt"
RESULTS_DIR = SCRIPT_DIR / "wpt-results"


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

SCHEMA = """\
CREATE TABLE IF NOT EXISTS tests (
  path            TEXT PRIMARY KEY,
  status          TEXT NOT NULL,
  title           TEXT,
  assertion       TEXT,
  css_spec        TEXT,
  spec_section    TEXT,
  spec_url        TEXT,
  has_script      INTEGER NOT NULL DEFAULT 0,
  diff_count      INTEGER NOT NULL DEFAULT 0,
  max_bounds_delta REAL NOT NULL DEFAULT 0.0,
  bounds_location TEXT,
  elapsed_s       REAL,
  timestamp       TEXT,
  notes           TEXT,
  reviewed        INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS diff_types (
  path      TEXT NOT NULL REFERENCES tests(path),
  diff_type TEXT NOT NULL,
  PRIMARY KEY (path, diff_type)
);

CREATE TABLE IF NOT EXISTS tags (
  path TEXT NOT NULL REFERENCES tests(path),
  tag  TEXT NOT NULL,
  PRIMARY KEY (path, tag)
);
"""


def init_db(conn):
    conn.executescript(SCHEMA)


# ---------------------------------------------------------------------------
# Pass 1 — WPT metadata extraction from test HTML
# ---------------------------------------------------------------------------

# Map spec URL hosts/paths to short spec names
SPEC_RE = re.compile(
    r'https?://(?:www\.)?(?:w3\.org|drafts\.csswg\.org)/(?:TR/)?([a-zA-Z0-9-]+?)(?:/|#|$)'
)


def extract_css_spec(url):
    """Extract a short spec identifier from a help URL."""
    m = SPEC_RE.search(url)
    if m:
        return m.group(1).lower().rstrip('/')
    return None


def extract_spec_section(url):
    """Extract the fragment (section) from a help URL."""
    if '#' in url:
        return url.split('#', 1)[1]
    return None


def parse_test_html(html_path):
    """Parse the first 4KB of a test HTML for WPT metadata."""
    try:
        with open(html_path, 'r', encoding='utf-8', errors='replace') as f:
            head = f.read(4096)
    except OSError:
        return {}

    result = {}

    # <title>...</title>
    m = re.search(r'<title[^>]*>(.*?)</title>', head, re.IGNORECASE | re.DOTALL)
    if m:
        result['title'] = m.group(1).strip()

    # <meta name="assert" content="...">
    m = re.search(
        r'<meta\s+name=["\']assert["\']\s+content=["\'](.*?)["\']',
        head, re.IGNORECASE | re.DOTALL
    )
    if m:
        result['assertion'] = m.group(1).strip()

    # <link rel="help" href="...">  (take first one)
    m = re.search(
        r'<link\s+rel=["\']help["\']\s+href=["\'](.*?)["\']',
        head, re.IGNORECASE
    )
    if m:
        url = m.group(1)
        result['spec_url'] = url
        result['css_spec'] = extract_css_spec(url)
        result['spec_section'] = extract_spec_section(url)

    # <script> presence
    result['has_script'] = 1 if re.search(r'<script', head, re.IGNORECASE) else 0

    return result


# ---------------------------------------------------------------------------
# Pass 2 — Cached results
# ---------------------------------------------------------------------------

def classify_diff(diff_str):
    """Classify a single diff string into a diff_type."""
    if 'extra baseline node' in diff_str or 'extra modified node' in diff_str:
        return 'structural'
    if 'wrapper inserted' in diff_str or 'wrapper removed' in diff_str:
        return 'structural'
    if 'moved to' in diff_str:
        return 'structural'
    if ' bounds ' in diff_str:
        return 'bounds'
    if ' style ' in diff_str:
        # Extract the property name: "... style <prop>: ..."
        m = re.search(r'style\s+(\S+?):', diff_str)
        if m:
            return f'style:{m.group(1)}'
        return 'style:unknown'
    return 'other'


def parse_bounds_delta(diff_str):
    """Extract the maximum numeric delta from a bounds diff."""
    # Pattern: "bounds <dim>: <val1> -> <val2>"
    m = re.search(r'bounds\s+\w+:\s+([\d.]+)\s*->\s*([\d.]+)', diff_str)
    if m:
        return abs(float(m.group(2)) - float(m.group(1)))
    return 0.0


def classify_bounds_location(diff_str):
    """Return 'container' if diff is on HTML/BODY, else 'content'."""
    path_part = diff_str.split('  ')[0] if '  ' in diff_str else ''
    path_upper = path_part.upper()
    # If the path is just /HTML or /HTML/BODY (no deeper elements)
    parts = [p for p in path_upper.split('/') if p]
    if all(p in ('HTML', 'BODY') for p in parts):
        return 'container'
    return 'content'


def process_result(result_data):
    """Process a single result JSON into classification fields."""
    diffs = result_data.get('diffs', [])
    diff_types = set()
    max_delta = 0.0
    locations = set()

    for d in diffs:
        diff_types.add(classify_diff(d))
        if 'bounds' in d:
            delta = parse_bounds_delta(d)
            if delta > max_delta:
                max_delta = delta
            locations.add(classify_bounds_location(d))

    # Determine bounds_location summary
    if not locations:
        bounds_loc = 'none'
    elif locations == {'container'}:
        bounds_loc = 'container_only'
    elif locations == {'content'}:
        bounds_loc = 'content'
    else:
        bounds_loc = 'mixed'

    return {
        'diff_count': len(diffs),
        'diff_types': sorted(diff_types),
        'max_bounds_delta': max_delta,
        'bounds_location': bounds_loc,
        'elapsed_s': result_data.get('elapsed_s'),
        'timestamp': result_data.get('timestamp'),
    }


# ---------------------------------------------------------------------------
# Pass 3 — Expectations → tags
# ---------------------------------------------------------------------------

REASON_TO_TAG = {
    # Major categories
    'requires tag-agnostic matching': 'requires-tag-agnostic-matching',
    'layout: bounds differ between test/ref': 'bounds-differ',
    'style: display property differs between test/ref': 'display-differs',
    'style: border property differs between test/ref': 'border-differs',
    'layout: body height collapse': 'body-height-collapse',
    'requires background-image comparison': 'requires-background-image-comparison',
    'layout: HTML element height discrepancy': 'html-height-discrepancy',
    'style: overflow computed value differs': 'overflow-differs',
    'style: z-index differs between test/ref': 'z-index-differs',
    'style: font property differs between test/ref': 'font-differs',
    'style: line-height differs between test/ref': 'line-height-differs',
    'style: text-align differs between test/ref': 'text-align-differs',
    'style: font-family computed value differs': 'font-family-differs',
    'style: text-decoration differs between test/ref': 'text-decoration-differs',
    'unformattable diff (formatter limitation)': 'unformattable-diff',
    'style: color property differs between test/ref': 'color-differs',
    # Minor style categories
    'style: cursor differs between test/ref': 'cursor-differs',
    'style: visibility differs between test/ref': 'visibility-differs',
    'style: opacity differs between test/ref': 'opacity-differs',
    'style: box-shadow differs between test/ref': 'box-shadow-differs',
    # Normalization
    'requires background-color body propagation normalization': 'requires-bg-propagation-normalization',
    'requires bg-color body propagation normalization': 'requires-bg-propagation-normalization',
    # Structural
    'structural: BODY extra baseline node (tree root mismatch)': 'structural-tree-root-mismatch',
    'structural: extra baseline node': 'structural-extra-baseline-node',
    # Errors
    'CDP connection lost': 'cdp-connection-lost',
    'capture timeout': 'capture-timeout',
    # Overflow:clip variants
    'overflow:clip \u2014 bounds differ between test/ref': 'overflow-clip-bounds-differ',
    "overflow:clip \u2014 computed style 'clip' vs 'hidden'": 'overflow-clip-vs-hidden',
    "overflow:clip \u2014 computed style 'clip' vs 'visible'": 'overflow-clip-vs-visible',
    # Text alignment edge cases
    "text-align-last \u2014 computed 'start' vs 'end'": 'text-align-last-start-vs-end',
    "text-align-last \u2014 computed 'start' vs 'center'": 'text-align-last-start-vs-center',
    "text-align:end \u2014 logical value 'end' vs physical 'start'": 'text-align-end-logical-vs-physical',
    # Specific edge cases
    'margin-trim not in sosie whitelist \u2014 bounds differ': 'margin-trim-bounds-differ',
    'position:relative \u2014 background-color differs (green vs transparent)': 'position-relative-bg-color-differs',
    'font-variant-alternates \u2014 font-family computed value differs': 'font-variant-alternates-font-family-differs',
    'first-available-font \u2014 bounds differ due to font metrics': 'first-available-font-bounds-differ',
    'a98-rgb color space \u2014 computed style string differs from rgb() equivalent': 'a98-rgb-color-space-differs',
    'display:contents with ::before/::after \u2014 text content differs': 'display-contents-pseudo-text-differs',
    'display:contents \u2014 different border-color between test and ref': 'display-contents-border-color-differs',
    'background-image with background-size \u2014 different DOM structure between test/ref': 'background-image-dom-structure-differs',
    'background-attachment test \u2014 different element structure between test/ref': 'background-attachment-structure-differs',
    'background-attachment \u2014 border-color differs between test and ref CSS': 'background-attachment-border-color-differs',
    'ascent/descent override \u2014 border-color and bounds differ': 'ascent-descent-override-differs',
}


def reason_to_tag(reason):
    """Convert an expectations.json reason string to a tag."""
    if reason in REASON_TO_TAG:
        return REASON_TO_TAG[reason]
    if reason.startswith('error:'):
        return 'extractor-error'
    # Fallback: slugify
    return re.sub(r'[^a-z0-9]+', '-', reason.lower()).strip('-')


# ---------------------------------------------------------------------------
# Tag → reason (for sync-expectations)
# ---------------------------------------------------------------------------

# Build reverse mapping, preferring the first entry for each tag
TAG_TO_REASON = {}
for _reason, _tag in REASON_TO_TAG.items():
    if _tag not in TAG_TO_REASON:
        TAG_TO_REASON[_tag] = _reason
TAG_TO_REASON['extractor-error'] = 'error: extractor exception'


def tag_to_reason(tag):
    """Convert a tag back to an expectations.json reason string."""
    return TAG_TO_REASON.get(tag, tag)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_bootstrap(args):
    """Build the classification DB from test HTML, cached results, and expectations."""
    if DB_PATH.exists():
        DB_PATH.unlink()

    conn = sqlite3.connect(str(DB_PATH))
    init_db(conn)

    # Load existing classification.json for preserved tags/notes
    prior = {}
    if CLASSIFICATION_JSON.exists():
        with open(CLASSIFICATION_JSON) as f:
            prior = json.load(f)

    # Load expectations
    with open(EXPECTATIONS_JSON) as f:
        expectations = json.load(f).get('wpt', {})

    # Discover all test paths from results directory
    result_paths = {}
    for root, _dirs, files in os.walk(RESULTS_DIR):
        for fname in files:
            if fname.endswith('.json'):
                full = Path(root) / fname
                # Convert filesystem path to test path
                rel = full.relative_to(RESULTS_DIR)
                # Remove .json suffix to get test path
                test_path = str(rel).removesuffix('.json')
                result_paths[test_path] = full

    print(f"Found {len(result_paths)} cached results")

    # Collect all known test paths (union of results + expectations)
    all_paths = set(result_paths.keys()) | set(expectations.keys())
    print(f"Total tests: {len(all_paths)}")

    rows = 0
    for test_path in sorted(all_paths):
        # Determine status
        exp = expectations.get(test_path, {})
        status = exp.get('status', 'pass')
        reason = exp.get('reason', '')

        # Pass 1: WPT metadata
        html_file = WPT_DIR / test_path
        meta = parse_test_html(html_file) if html_file.exists() else {}

        # Pass 2: Cached results
        result_file = result_paths.get(test_path)
        result_info = {}
        if result_file and result_file.exists():
            with open(result_file) as f:
                result_data = json.load(f)
            result_info = process_result(result_data)
            # Use result status if available (more authoritative)
            if 'status' in result_data:
                status = result_data['status']

        # Prior classification data (tags, notes, reviewed)
        prior_entry = prior.get(test_path, {})

        conn.execute(
            """INSERT OR REPLACE INTO tests
               (path, status, title, assertion, css_spec, spec_section, spec_url,
                has_script, diff_count, max_bounds_delta, bounds_location,
                elapsed_s, timestamp, notes, reviewed)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                test_path,
                status,
                meta.get('title'),
                meta.get('assertion'),
                meta.get('css_spec'),
                meta.get('spec_section'),
                meta.get('spec_url'),
                meta.get('has_script', 0),
                result_info.get('diff_count', 0),
                result_info.get('max_bounds_delta', 0.0),
                result_info.get('bounds_location', 'none'),
                result_info.get('elapsed_s'),
                result_info.get('timestamp'),
                prior_entry.get('notes'),
                1 if prior_entry.get('reviewed') else 0,
            )
        )

        # Diff types
        for dt in result_info.get('diff_types', []):
            conn.execute(
                "INSERT OR IGNORE INTO diff_types (path, diff_type) VALUES (?, ?)",
                (test_path, dt)
            )

        # Tags: from expectations reason + prior classification
        tags_to_add = set()
        if reason:
            tags_to_add.add(reason_to_tag(reason))
        for t in prior_entry.get('tags', []):
            tags_to_add.add(t)
        for t in tags_to_add:
            conn.execute(
                "INSERT OR IGNORE INTO tags (path, tag) VALUES (?, ?)",
                (test_path, t)
            )

        rows += 1

    conn.commit()
    conn.close()
    print(f"Bootstrapped {rows} tests into {DB_PATH.name}")


def cmd_export(args):
    """Export the DB to classification.json."""
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row

    result = {}
    for row in conn.execute("SELECT * FROM tests ORDER BY path"):
        path = row['path']
        entry = {
            'status': row['status'],
            'title': row['title'],
            'assertion': row['assertion'],
            'css_spec': row['css_spec'],
            'spec_section': row['spec_section'],
            'spec_url': row['spec_url'],
            'has_script': bool(row['has_script']),
            'diff_types': [],
            'diff_count': row['diff_count'],
            'max_bounds_delta': row['max_bounds_delta'],
            'bounds_location': row['bounds_location'],
            'tags': [],
            'notes': row['notes'],
            'reviewed': bool(row['reviewed']),
        }
        result[path] = entry

    for row in conn.execute("SELECT path, diff_type FROM diff_types ORDER BY path, diff_type"):
        if row['path'] in result:
            result[row['path']]['diff_types'].append(row['diff_type'])

    for row in conn.execute("SELECT path, tag FROM tags ORDER BY path, tag"):
        if row['path'] in result:
            result[row['path']]['tags'].append(row['tag'])

    conn.close()

    with open(CLASSIFICATION_JSON, 'w') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write('\n')

    print(f"Exported {len(result)} tests to {CLASSIFICATION_JSON.name}")


def cmd_import(args):
    """Import classification.json into the DB."""
    if not CLASSIFICATION_JSON.exists():
        print(f"Error: {CLASSIFICATION_JSON.name} not found", file=sys.stderr)
        sys.exit(1)

    with open(CLASSIFICATION_JSON) as f:
        data = json.load(f)

    if DB_PATH.exists():
        DB_PATH.unlink()

    conn = sqlite3.connect(str(DB_PATH))
    init_db(conn)

    for path, entry in sorted(data.items()):
        conn.execute(
            """INSERT OR REPLACE INTO tests
               (path, status, title, assertion, css_spec, spec_section, spec_url,
                has_script, diff_count, max_bounds_delta, bounds_location,
                elapsed_s, timestamp, notes, reviewed)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                path,
                entry.get('status', 'pass'),
                entry.get('title'),
                entry.get('assertion'),
                entry.get('css_spec'),
                entry.get('spec_section'),
                entry.get('spec_url'),
                1 if entry.get('has_script') else 0,
                entry.get('diff_count', 0),
                entry.get('max_bounds_delta', 0.0),
                entry.get('bounds_location', 'none'),
                entry.get('elapsed_s'),
                entry.get('timestamp'),
                entry.get('notes'),
                1 if entry.get('reviewed') else 0,
            )
        )

        for dt in entry.get('diff_types', []):
            conn.execute(
                "INSERT OR IGNORE INTO diff_types (path, diff_type) VALUES (?, ?)",
                (path, dt)
            )

        for tag in entry.get('tags', []):
            conn.execute(
                "INSERT OR IGNORE INTO tags (path, tag) VALUES (?, ?)",
                (path, tag)
            )

    conn.commit()
    conn.close()
    print(f"Imported {len(data)} tests into {DB_PATH.name}")


def cmd_summary(args):
    """Print a classification summary table."""
    conn = sqlite3.connect(str(DB_PATH))

    total = conn.execute("SELECT COUNT(*) FROM tests").fetchone()[0]
    print(f"Total tests: {total}")
    print()

    # Status breakdown
    print("=== Status ===")
    for row in conn.execute(
        "SELECT status, COUNT(*) as n FROM tests GROUP BY status ORDER BY n DESC"
    ):
        pct = 100.0 * row[1] / total if total else 0
        print(f"  {row[0]:10s}  {row[1]:6d}  ({pct:5.1f}%)")
    print()

    # Tag breakdown
    print("=== Tags ===")
    for row in conn.execute(
        "SELECT tag, COUNT(*) as n FROM tags GROUP BY tag ORDER BY n DESC"
    ):
        pct = 100.0 * row[1] / total if total else 0
        print(f"  {row[0]:50s}  {row[1]:6d}  ({pct:5.1f}%)")
    print()

    # Diff type breakdown
    print("=== Diff types ===")
    for row in conn.execute(
        "SELECT diff_type, COUNT(*) as n FROM diff_types GROUP BY diff_type ORDER BY n DESC"
    ):
        pct = 100.0 * row[1] / total if total else 0
        print(f"  {row[0]:50s}  {row[1]:6d}  ({pct:5.1f}%)")
    print()

    # Spec breakdown (top 15)
    print("=== Top specs (by test count) ===")
    for row in conn.execute(
        """SELECT COALESCE(css_spec, '(none)') as spec, COUNT(*) as n,
                  SUM(status = 'pass') as passing
           FROM tests GROUP BY css_spec ORDER BY n DESC LIMIT 15"""
    ):
        print(f"  {row[0]:40s}  {row[1]:6d} total  {row[2]:6d} pass")
    print()

    # Bounds stats
    print("=== Bounds delta distribution (xfail only) ===")
    for label, lo, hi in [
        ('= 0', -0.01, 0.01),
        ('0 < d <= 5', 0.01, 5),
        ('5 < d <= 20', 5, 20),
        ('> 20', 20, 1e9),
    ]:
        n = conn.execute(
            "SELECT COUNT(*) FROM tests WHERE status != 'pass' AND max_bounds_delta > ? AND max_bounds_delta <= ?",
            (lo, hi)
        ).fetchone()[0]
        print(f"  {label:20s}  {n:6d}")
    print()

    # Has script
    n_script = conn.execute("SELECT COUNT(*) FROM tests WHERE has_script = 1").fetchone()[0]
    print(f"Tests with <script>: {n_script}")

    # Reviewed
    n_reviewed = conn.execute("SELECT COUNT(*) FROM tests WHERE reviewed = 1").fetchone()[0]
    print(f"Reviewed: {n_reviewed}/{total}")

    conn.close()


def cmd_query(args):
    """Run arbitrary SQL and print results."""
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    try:
        cursor = conn.execute(args.sql)
        rows = cursor.fetchall()
        if not rows:
            print("(no results)")
            return

        keys = rows[0].keys()
        # Print header
        print('\t'.join(keys))
        print('\t'.join('-' * len(k) for k in keys))
        for row in rows:
            print('\t'.join(str(row[k]) if row[k] is not None else '' for k in keys))

        print(f"\n({len(rows)} rows)")
    except sqlite3.Error as e:
        print(f"SQL error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        conn.close()


def cmd_tag(args):
    """Add a tag to a test."""
    conn = sqlite3.connect(str(DB_PATH))
    # Verify test exists
    row = conn.execute("SELECT path FROM tests WHERE path = ?", (args.path,)).fetchone()
    if not row:
        print(f"Error: test '{args.path}' not found in DB", file=sys.stderr)
        sys.exit(1)

    conn.execute(
        "INSERT OR IGNORE INTO tags (path, tag) VALUES (?, ?)",
        (args.path, args.tag)
    )
    conn.commit()
    conn.close()
    print(f"Tagged '{args.path}' with '{args.tag}'")


def cmd_note(args):
    """Add a note to a test (appends to existing notes)."""
    conn = sqlite3.connect(str(DB_PATH))
    row = conn.execute("SELECT path, notes FROM tests WHERE path = ?", (args.path,)).fetchone()
    if not row:
        print(f"Error: test '{args.path}' not found in DB", file=sys.stderr)
        sys.exit(1)

    existing = row[1] or ''
    new_notes = (existing + '\n' + args.text).strip() if existing else args.text
    conn.execute("UPDATE tests SET notes = ? WHERE path = ?", (new_notes, args.path))
    conn.commit()
    conn.close()
    print(f"Note added to '{args.path}'")


def cmd_sync_expectations(args):
    """Update expectations.json reasons from the DB's primary tag."""
    conn = sqlite3.connect(str(DB_PATH))

    with open(EXPECTATIONS_JSON) as f:
        data = json.load(f)

    wpt = data.get('wpt', {})
    updated = 0

    for path in wpt:
        # Get primary tag (first tag alphabetically, matching the original reason mapping)
        row = conn.execute(
            "SELECT tag FROM tags WHERE path = ? ORDER BY tag LIMIT 1",
            (path,)
        ).fetchone()
        if row:
            new_reason = tag_to_reason(row[0])
            if wpt[path].get('reason') != new_reason:
                wpt[path]['reason'] = new_reason
                updated += 1

    conn.close()

    with open(EXPECTATIONS_JSON, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')

    print(f"Updated {updated} reasons in {EXPECTATIONS_JSON.name}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='WPT reftest classification database'
    )
    sub = parser.add_subparsers(dest='command')

    sub.add_parser('bootstrap', help='Build DB from sources')
    sub.add_parser('export', help='Export DB to classification.json')
    sub.add_parser('import', help='Import classification.json into DB')
    sub.add_parser('summary', help='Print classification summary')

    p_query = sub.add_parser('query', help='Run arbitrary SQL')
    p_query.add_argument('sql', help='SQL query to execute')

    p_tag = sub.add_parser('tag', help='Add a tag to a test')
    p_tag.add_argument('path', help='Test path')
    p_tag.add_argument('tag', help='Tag to add')

    p_note = sub.add_parser('note', help='Add a note to a test')
    p_note.add_argument('path', help='Test path')
    p_note.add_argument('text', help='Note text')

    sub.add_parser('sync-expectations', help='Update expectations.json reasons from DB')

    args = parser.parse_args()

    commands = {
        'bootstrap': cmd_bootstrap,
        'export': cmd_export,
        'import': cmd_import,
        'summary': cmd_summary,
        'query': cmd_query,
        'tag': cmd_tag,
        'note': cmd_note,
        'sync-expectations': cmd_sync_expectations,
    }

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    commands[args.command](args)


if __name__ == '__main__':
    main()

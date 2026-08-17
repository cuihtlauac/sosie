#!/usr/bin/env python3
"""WPT corpus coverage analyzer.

Answers: which files of the full WPT tree (at the pinned commit) does
sosie's reftest discovery include, and what does it leave out, and why?

Reads the ENTIRE tree via git plumbing (the local object store holds all
blobs even though the working tree is a sparse checkout), replicates the
discovery semantics of ext_test_lib.ml byte-for-byte to attribute every
candidate file to exactly one category, and validates the result against
classification.json (the discovered-test ground truth) before reporting.

Usage:
    wpt_coverage.py scan       # Full-tree scan -> coverage.db (rebuilds)
    wpt_coverage.py validate   # included set == classification.json keys
    wpt_coverage.py report     # coverage.db -> COVERAGE.md + coverage-summary.json
    wpt_coverage.py summary    # Print category breakdown
    wpt_coverage.py query SQL  # Run arbitrary SQL
"""

import argparse
import json
import os
import posixpath
import re
import sqlite3
import subprocess
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DB_PATH = SCRIPT_DIR / "coverage.db"
WPT_DIR = SCRIPT_DIR / "wpt"
MANIFEST_JSON = SCRIPT_DIR / "manifest.json"
CLASSIFICATION_JSON = SCRIPT_DIR / "classification.json"
COVERAGE_MD = SCRIPT_DIR / "COVERAGE.md"
SUMMARY_JSON = SCRIPT_DIR / "coverage-summary.json"

CANDIDATE_EXTS = ('.html', '.xhtml', '.xht', '.svg')
# Extensions the OCaml walker accepts (ext_test_lib.ml acc_if_reftest)
OCAML_EXTS = ('.html', '.xhtml', '.xht')


# ---------------------------------------------------------------------------
# Regexes — mirror of ext_test_lib.ml parsing (as of the 2026-08 rewrite the
# OCaml parser accepts everything the broad scan does, so there is a single
# tier; keep these in lockstep with ext_test_lib.ml)
# ---------------------------------------------------------------------------

# Tag spans end at the next '<' or '>' (malformed-tag recovery, matching
# link_tag_re in ext_test_lib.ml).
LINK_TAG_RE = re.compile(rb'<link\s[^<>]*', re.IGNORECASE)
META_TAG_RE = re.compile(rb'<meta\s[^<>]*', re.IGNORECASE)
TESTHARNESS_RE = re.compile(rb'testharness\.js', re.IGNORECASE)

# ext_test_lib.ml nondeterministic_re, checked on the whole file BEFORE
# link parsing (parse_reftest_links_from_file).
NONDET_RE = re.compile(rb'@keyframes|animation\s*:|transition\s*:|transition-')


def get_attr(tag, name):
    """Extract an attribute value (quoted or bare) from a tag's bytes.

    Mirrors attr_re in ext_test_lib.ml: a leading \\s anchors the name,
    bare values run to the next whitespace."""
    m = re.search(
        rb'\s' + name + rb'''\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))''',
        tag, re.IGNORECASE)
    if not m:
        return None, False
    if m.group(2) is not None:
        return m.group(2), True
    if m.group(3) is not None:
        return m.group(3), True
    return m.group(4), False


def broad_link_scan(body):
    """All <link> rel=match / rel=mismatch hrefs, any quoting, any case.

    Returns (match_links, mismatch_links), each a list of (href_bytes,
    quoted) in document order, deduplicated by href per rel — mirroring
    parse_reftest_links / parse_mismatch_links in ext_test_lib.ml.
    """
    match_links = []
    mismatch_links = []
    seen_match = set()
    seen_mismatch = set()
    for m in LINK_TAG_RE.finditer(body):
        tag = m.group(0)
        rel, _ = get_attr(tag, rb'rel')
        if rel is None:
            continue
        tokens = rel.lower().split()
        href, quoted = get_attr(tag, rb'href')
        if not href:
            continue
        if b'match' in tokens and href not in seen_match:
            seen_match.add(href)
            match_links.append((href, quoted))
        if b'mismatch' in tokens and href not in seen_mismatch:
            seen_mismatch.add(href)
            mismatch_links.append((href, quoted))
    return match_links, mismatch_links


def has_fuzzy_meta(body):
    for m in META_TAG_RE.finditer(body):
        name, _ = get_attr(m.group(0), rb'name')
        if name and name.lower() == b'fuzzy':
            return True
    return False


# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

def module_of(path):
    """'css/css-flexbox/x.html' -> 'css/css-flexbox'; 'html/x.html' -> 'html'."""
    parts = path.split('/')
    if parts[0] == 'css' and len(parts) > 2:
        return 'css/' + parts[1]
    return parts[0]


def in_support_or_reference(path):
    """Mirror ext_test_lib.ml: any path component equal to reference/support."""
    return any(p in ('reference', 'support') for p in path.split('/'))


def resolve_href(test_path, href):
    """Mirror ext_test_lib.ml ref resolution: absolute hrefs are wpt-root
    relative; otherwise relative to the test's directory."""
    if href.startswith('/'):
        return href[1:]
    return posixpath.join(posixpath.dirname(test_path), href)


def ref_in_worktree(resolved):
    """Mirror Sys.file_exists on the sparse working tree (OS resolves '..')."""
    return os.path.exists(WPT_DIR / resolved)


# ---------------------------------------------------------------------------
# Git plumbing
# ---------------------------------------------------------------------------

def git_head_commit():
    return subprocess.run(
        ['git', '-C', str(WPT_DIR), 'rev-parse', 'HEAD'],
        capture_output=True, check=True, text=True).stdout.strip()


def git_ls_tree():
    """Return (full_tree_paths, candidates) where candidates is a list of
    (path, sha, size) for reftest-candidate extensions."""
    out = subprocess.run(
        ['git', '-C', str(WPT_DIR), 'ls-tree', '-r', '-z', '-l', 'HEAD'],
        capture_output=True, check=True).stdout
    full_tree = set()
    candidates = []
    for entry in out.split(b'\0'):
        if not entry:
            continue
        meta, path_b = entry.split(b'\t', 1)
        mode, typ, sha, size = meta.split()
        if typ != b'blob' or mode not in (b'100644', b'100755'):
            continue
        path = path_b.decode('latin-1')
        full_tree.add(path)
        if path.endswith(CANDIDATE_EXTS):
            candidates.append((path, sha.decode('ascii'), int(size)))
    return full_tree, candidates


def stream_blobs(candidates):
    """Yield (path, sha, size, body) for each candidate via one pipelined
    `git cat-file --batch` subprocess. A writer thread feeds the SHAs to
    avoid pipe deadlock; --batch answers strictly in request order."""
    proc = subprocess.Popen(
        ['git', '-C', str(WPT_DIR), 'cat-file', '--batch'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE)

    def feed():
        for _, sha, _ in candidates:
            proc.stdin.write(sha.encode('ascii') + b'\n')
        proc.stdin.close()

    writer = threading.Thread(target=feed, daemon=True)
    writer.start()

    for path, sha, _ in candidates:
        header = proc.stdout.readline()
        parts = header.split()
        if len(parts) != 3 or parts[1] != b'blob':
            raise RuntimeError(f'unexpected cat-file header for {path}: {header!r}')
        size = int(parts[2])
        body = proc.stdout.read(size)
        proc.stdout.read(1)  # trailing LF
        yield path, sha, size, body

    writer.join()
    proc.stdout.close()
    proc.wait()


# ---------------------------------------------------------------------------
# Attribution
# ---------------------------------------------------------------------------

def load_groups():
    with open(MANIFEST_JSON) as f:
        return json.load(f)['wpt']['groups']


def extract_features(path, body):
    """All per-file facts needed for attribution and flags."""
    match_links, mismatch_links = broad_link_scan(body)
    return {
        'match_links': match_links,
        'mismatch_links': mismatch_links,
        'nondet': bool(NONDET_RE.search(body)),
        'fuzzy': has_fuzzy_meta(body),
        'testharness': bool(TESTHARNESS_RE.search(body)),
        'crashtest': 'crashtests' in path.split('/'),
        'manual': Path(path).stem.endswith('-manual'),
        'print_reftest': '-print' in Path(path).name
                         or 'printing' in path.split('/'),
    }


def attribute(path, feat, in_scope, full_tree):
    """Primary category via the discovery rule chain (first hit wins).

    Mirrors ext_test_lib.ml discovery: a file with any rel=match link is a
    Match test (mismatch links ignored); a file with only rel=mismatch
    links is a Mismatch test. A test is included when at least one of its
    kind's refs exists (the runner tries them in order).

    For out-of-scope files also returns would_be: the category the same
    chain would assign if the module were ingested, with ref existence
    checked against the full tree (nothing out of scope is checked out).
    Returns (category, would_be, ref_in_wt, ref_in_ft).
    """
    if in_support_or_reference(path):
        return 'excluded-support-reference-path', None, None, None

    links = feat['match_links'] or feat['mismatch_links']
    hrefs = [h.decode('latin-1') for h, _ in links]
    resolved = [resolve_href(path, h) for h in hrefs]
    any_in_ft = any(posixpath.normpath(r) in full_tree for r in resolved)

    def chain(ref_exists_fulltree_only):
        if not path.endswith(OCAML_EXTS):
            return 'not-scanned-svg-extension', None
        if not hrefs:
            return 'not-a-reftest', None
        if feat['nondet']:
            return 'excluded-nondeterministic', None
        if ref_exists_fulltree_only:
            if not any_in_ft:
                return 'missed-ref-truly-absent', None
            return 'included', None
        in_wt = any(ref_in_worktree(r) for r in resolved)
        if not in_wt:
            if any_in_ft:
                return 'missed-ref-missing-in-sparse', in_wt
            return 'missed-ref-truly-absent', in_wt
        return 'included', in_wt

    if not in_scope:
        would_be, _ = chain(ref_exists_fulltree_only=True)
        return 'out-of-scope-module', would_be, None, any_in_ft

    category, in_wt = chain(ref_exists_fulltree_only=False)
    return category, None, in_wt, any_in_ft


# ---------------------------------------------------------------------------
# scan
# ---------------------------------------------------------------------------

def cmd_scan(args):
    marker = WPT_DIR / '.commit'
    with open(MANIFEST_JSON) as f:
        manifest_commit = json.load(f)['wpt']['commit']
    # Marker line 1 is the commit; later lines record the sparse patterns.
    if marker.exists() and \
            marker.read_text().splitlines()[0].strip() != manifest_commit:
        print(f"warning: wpt/.commit != manifest commit {manifest_commit}; "
              "worktree-based checks may be stale", file=sys.stderr)

    groups = load_groups()
    group_prefixes = tuple(g + '/' for g in groups)
    commit = git_head_commit()
    if commit != manifest_commit:
        print(f"warning: wpt HEAD {commit} != manifest commit {manifest_commit}",
              file=sys.stderr)

    print(f"Enumerating tree at {commit} ...")
    full_tree, candidates = git_ls_tree()
    print(f"  {len(full_tree)} files in tree, {len(candidates)} candidates "
          f"({'/'.join(e.lstrip('.') for e in CANDIDATE_EXTS)})")

    file_rows = []
    link_rows = []
    # path -> True for every file that is itself a reftest, for the
    # chained-ref pass
    reftest_map = {}

    print("Scanning blobs via git cat-file --batch ...")
    n = 0
    for path, sha, size, body in stream_blobs(candidates):
        feat = extract_features(path, body)
        in_scope = path.startswith(group_prefixes)
        category, would_be, in_wt, in_ft = attribute(path, feat, in_scope, full_tree)

        # Kind mirrors ext_test_lib.ml: match links win; mismatch-only
        # files are mismatch tests.
        if feat['match_links']:
            kind = 'match'
        elif feat['mismatch_links']:
            kind = 'mismatch'
        else:
            kind = None

        resolved_kind = []
        ord_ = 0
        for rel_name, rel_links in (('match', feat['match_links']),
                                    ('mismatch', feat['mismatch_links'])):
            for href_b, quoted in rel_links:
                href = href_b.decode('latin-1')
                resolved = posixpath.normpath(resolve_href(path, href))
                if rel_name == kind:
                    resolved_kind.append(resolved)
                link_rows.append((path, ord_, rel_name, href,
                                  1 if quoted else 0, resolved,
                                  1 if resolved in full_tree else 0))
                ord_ += 1
        if kind is not None:
            reftest_map[path] = True

        file_rows.append([
            path, sha, size, Path(path).suffix.lstrip('.'), module_of(path),
            1 if in_scope else 0, category, would_be, kind,
            resolved_kind[0] if resolved_kind else None,
            len(feat['match_links']), len(feat['mismatch_links']),
            1 if feat['fuzzy'] else 0, 1 if feat['nondet'] else 0,
            1 if feat['testharness'] else 0,
            None if in_wt is None else int(in_wt),
            None if in_ft is None else int(in_ft),
            0,  # chained_ref, filled below
            1 if feat['print_reftest'] else 0,
        ])
        n += 1
        if n % 10000 == 0:
            print(f"  {n}/{len(candidates)}")

    # Chained-ref post-pass: is the first ref itself a reftest?
    for row in file_rows:
        path, first_ref = row[0], row[9]
        if first_ref is not None and first_ref != path and first_ref in reftest_map:
            row[17] = 1

    if DB_PATH.exists():
        DB_PATH.unlink()
    conn = sqlite3.connect(str(DB_PATH))
    conn.executescript("""\
CREATE TABLE scan_meta (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE files (
  path            TEXT PRIMARY KEY,
  sha             TEXT NOT NULL,
  size            INTEGER NOT NULL,
  ext             TEXT NOT NULL,
  module          TEXT NOT NULL,
  in_scope        INTEGER NOT NULL,
  category        TEXT NOT NULL,
  would_be        TEXT,
  kind            TEXT,
  first_ref       TEXT,
  match_count     INTEGER NOT NULL DEFAULT 0,
  mismatch_count  INTEGER NOT NULL DEFAULT 0,
  fuzzy           INTEGER NOT NULL DEFAULT 0,
  nondet          INTEGER NOT NULL DEFAULT 0,
  testharness     INTEGER NOT NULL DEFAULT 0,
  ref_in_worktree INTEGER,
  ref_in_fulltree INTEGER,
  chained_ref     INTEGER NOT NULL DEFAULT 0,
  print_reftest   INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_files_cat ON files(category);
CREATE INDEX idx_files_mod ON files(module, category);
CREATE TABLE reftest_links (
  path TEXT NOT NULL, ord INTEGER NOT NULL, rel TEXT NOT NULL,
  href TEXT NOT NULL, quoted INTEGER NOT NULL, resolved TEXT,
  in_fulltree INTEGER,
  PRIMARY KEY (path, ord)
);
""")
    conn.executemany(
        "INSERT INTO files VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        file_rows)
    conn.executemany("INSERT INTO reftest_links VALUES (?,?,?,?,?,?,?)",
                     link_rows)
    meta = {
        'wpt_commit': commit,
        'scan_timestamp': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'tree_file_total': str(len(full_tree)),
        'candidate_total': str(len(candidates)),
        'groups': json.dumps(groups),
    }
    conn.executemany("INSERT INTO scan_meta VALUES (?, ?)", meta.items())
    conn.commit()
    conn.close()
    print(f"Scanned {len(file_rows)} candidates into {DB_PATH.name}")


# ---------------------------------------------------------------------------
# validate
# ---------------------------------------------------------------------------

def cmd_validate(args):
    with open(CLASSIFICATION_JSON) as f:
        ground_truth = set(json.load(f).keys())

    conn = sqlite3.connect(str(DB_PATH))
    scanned = {row[0] for row in
               conn.execute("SELECT path FROM files WHERE category = 'included'")}
    conn.close()

    only_scanner = sorted(scanned - ground_truth)
    only_truth = sorted(ground_truth - scanned)
    print(f"scanner included:      {len(scanned)}")
    print(f"classification.json:   {len(ground_truth)}")
    print(f"only in scanner:       {len(only_scanner)}")
    print(f"only in classification: {len(only_truth)}")
    for label, paths in (('scanner', only_scanner), ('classification', only_truth)):
        for p in paths[:50]:
            print(f"  only-in-{label}: {p}")
        if len(paths) > 50:
            print(f"  ... and {len(paths) - 50} more")
    if only_scanner or only_truth:
        print("VALIDATION FAILED — scanner disagrees with discovery", file=sys.stderr)
        sys.exit(1)
    print("VALIDATION OK — scanner reproduces discovery exactly")


# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------

IN_SCOPE_WATERFALL = [
    ('excluded-support-reference-path', 'reference/ or support/ path'),
    ('not-a-reftest', 'no reftest link (testharness, helpers, ...)'),
    ('excluded-nondeterministic', 'animation/transition/@keyframes'),
    ('not-scanned-svg-extension', '.svg extension (walker skips)'),
    ('missed-ref-missing-in-sparse', 'all refs outside sparse checkout'),
    ('missed-ref-truly-absent', 'no ref exists in full tree'),
    ('included', 'discovered reftests'),
]

GAP_CATEGORIES = {
    'missed-ref-missing-in-sparse':
        'Add the missing paths (or their directories) to the sparse '
        'checkout in fetch.sh / manifest.json support_paths.',
    'missed-ref-truly-absent':
        'Broken links upstream, or hrefs the resolver mishandles; '
        'nothing to recover without upstream fixes.',
    'not-scanned-svg-extension':
        'Accept .svg test files in acc_if_reftest (WPT allows SVG '
        'reftests); extractor already runs in any page Chromium loads.',
}


def q1(conn, sql, params=()):
    return conn.execute(sql, params).fetchone()[0]


def cmd_report(args):
    conn = sqlite3.connect(str(DB_PATH))
    meta = dict(conn.execute("SELECT key, value FROM scan_meta"))
    total_in_scope = q1(conn, "SELECT COUNT(*) FROM files WHERE in_scope = 1")
    total_out = q1(conn, "SELECT COUNT(*) FROM files WHERE in_scope = 0")
    included = q1(conn, "SELECT COUNT(*) FROM files WHERE category = 'included'")

    with open(CLASSIFICATION_JSON) as f:
        truth_n = len(json.load(f))
    validation_ok = included == truth_n

    ext_counts = conn.execute(
        "SELECT ext, COUNT(*) FROM files GROUP BY ext ORDER BY 2 DESC").fetchall()
    cat_in = dict(conn.execute(
        "SELECT category, COUNT(*) FROM files WHERE in_scope = 1 GROUP BY category"))

    # Out-of-scope modules ranked by recoverable value
    mod_rows = conn.execute("""
        SELECT module,
               COUNT(*) AS candidates,
               SUM(would_be = 'included') AS would_included,
               SUM(would_be = 'included' AND kind = 'mismatch') AS mismatch,
               SUM(would_be = 'excluded-nondeterministic') AS nondet,
               SUM(category = 'out-of-scope-module' AND fuzzy = 1) AS fuzzy
        FROM files WHERE in_scope = 0
        GROUP BY module
        HAVING would_included > 0
        ORDER BY would_included DESC
    """).fetchall()

    flags = {
        'mismatch_included': q1(conn,
            "SELECT COUNT(*) FROM files WHERE category = 'included' "
            "AND kind = 'mismatch'"),
        'mixed_included': q1(conn,
            "SELECT COUNT(*) FROM files WHERE category = 'included' "
            "AND kind = 'match' AND mismatch_count > 0"),
        'fuzzy_included': q1(conn,
            "SELECT COUNT(*) FROM files WHERE category = 'included' AND fuzzy = 1"),
        'fuzzy_total': q1(conn, "SELECT COUNT(*) FROM files WHERE fuzzy = 1"),
        'alternates_included': q1(conn,
            "SELECT COUNT(*) FROM files WHERE category = 'included' "
            "AND match_count > 1"),
        'chained_included': q1(conn,
            "SELECT COUNT(*) FROM files WHERE category = 'included' "
            "AND chained_ref = 1"),
        'print_reftests': q1(conn,
            "SELECT COUNT(*) FROM files WHERE print_reftest = 1 "
            "AND (category = 'included' OR would_be = 'included')"),
    }

    lines = []
    w = lines.append
    w('# WPT corpus coverage')
    w('')
    w('Generated by `wpt_coverage.py report` — do not edit by hand.')
    w('Regenerate: `python3 test/external/wpt_coverage.py scan && '
      'python3 test/external/wpt_coverage.py report`')
    w('')
    w(f"- WPT commit: `{meta['wpt_commit']}`")
    w(f"- Scan date: {meta['scan_timestamp']}")
    w(f"- Files in tree: {meta['tree_file_total']}; "
      f"reftest candidates (html/xht/xhtml/svg): {meta['candidate_total']}")
    w('- Worktree-dependent splits reflect the fetch.sh sparse checkout '
      'at scan time.')
    w('')
    w('## Corpus totals')
    w('')
    w('| | count |')
    w('|---|---:|')
    for ext, n in ext_counts:
        w(f'| .{ext} candidates | {n} |')
    w(f'| in scope (37 manifest groups) | {total_in_scope} |')
    w(f'| out of scope | {total_out} |')
    w('')
    w('## In-scope waterfall')
    w('')
    w('Every candidate inside the 37 ingested groups, attributed to the '
      'first discovery rule that stops it:')
    w('')
    w('| category | count | meaning |')
    w('|---|---:|---|')
    for cat, desc in IN_SCOPE_WATERFALL:
        w(f'| {cat} | {cat_in.get(cat, 0)} | {desc} |')
    w(f'| **total** | **{total_in_scope}** | |')
    w('')
    w('## Validation')
    w('')
    status = 'OK' if validation_ok else 'FAILED'
    w(f'Scanner `included` = {included}; classification.json = {truth_n} '
      f'— **{status}**. (`wpt_coverage.py validate` checks path-level '
      'equality.)')
    w('')
    w('## Gaps inside the ingested groups')
    w('')
    for cat, fix in GAP_CATEGORIES.items():
        n = cat_in.get(cat, 0)
        w(f'### {cat} ({n})')
        w('')
        examples = conn.execute(
            "SELECT path FROM files WHERE in_scope = 1 AND category = ? "
            "ORDER BY path LIMIT 5", (cat,)).fetchall()
        for (p,) in examples:
            w(f'- `{p}`')
        if n:
            w('')
        w(f'Fix sketch: {fix}')
        w('')
    w('## Out-of-scope modules by recoverable value')
    w('')
    w('`would-included` = deterministic match-reftests whose reference '
      'exists in the full tree — the tests sosie would gain by adding the '
      'module to manifest.json groups (plus checking out its refs).')
    w('')
    w('| module | candidates | would-included | of which mismatch | nondet | fuzzy |')
    w('|---|---:|---:|---:|---:|---:|')
    for mod, cand, inc, mis, nod, fuz in mod_rows:
        w(f'| {mod} | {cand} | {inc} | {mis} | {nod} | {fuz} |')
    tot = [sum(r[i] for r in mod_rows) for i in range(1, 6)]
    w(f'| **total** | **{tot[0]}** | **{tot[1]}** | **{tot[2]}** | '
      f'**{tot[3]}** | **{tot[4]}** |')
    w('')
    w('## Semantic opportunities')
    w('')
    w(f"- **Mismatch reftests as negative controls**: "
      f"{flags['mismatch_included']} included (kind=mismatch). "
      "`rel=\"mismatch\"` asserts the pages render DIFFERENTLY — the "
      "runner inverts the verdict, so an Equivalent result is a measured "
      "false negative (sensitivity gap). "
      f"{flags['mixed_included']} included match tests also carry mismatch "
      "links, which are ignored for now (compared against match refs only).")
    w(f"- **Fuzzy reftests**: {flags['fuzzy_included']} of the included "
      f"tests carry `<meta name=fuzzy>` (expected pixel deviation; "
      f"candidates for principled xfail), {flags['fuzzy_total']} "
      "corpus-wide.")
    w(f"- **Alternate references**: {flags['alternates_included']} included "
      "tests have multiple `rel=match` links; WPT semantics is pass-if-ANY-"
      "matches, sosie compares only the first.")
    w(f"- **Chained references**: {flags['chained_included']} included "
      "tests point at a reference that is itself a reftest (A=B=C chain); "
      "sosie compares only the first hop.")
    w(f"- **Print reftests**: {flags['print_reftests']} (in scope or "
      "recoverable) target paged media; captured with a screen viewport "
      "today.")
    w('')

    COVERAGE_MD.write_text('\n'.join(lines))
    print(f"Wrote {COVERAGE_MD.name}")

    summary = {
        'wpt_commit': meta['wpt_commit'],
        'scan_timestamp': meta['scan_timestamp'],
        'tree_file_total': int(meta['tree_file_total']),
        'candidate_total': int(meta['candidate_total']),
        'in_scope_total': total_in_scope,
        'out_of_scope_total': total_out,
        'validation_ok': validation_ok,
        'in_scope_categories': cat_in,
        'out_of_scope_modules': [
            {'module': r[0], 'candidates': r[1], 'would_included': r[2],
             'mismatch': r[3], 'nondet': r[4], 'fuzzy': r[5]}
            for r in mod_rows],
        'flags': flags,
    }
    with open(SUMMARY_JSON, 'w') as f:
        json.dump(summary, f, indent=2)
        f.write('\n')
    print(f"Wrote {SUMMARY_JSON.name}")
    conn.close()


# ---------------------------------------------------------------------------
# summary / query
# ---------------------------------------------------------------------------

def cmd_summary(args):
    conn = sqlite3.connect(str(DB_PATH))
    total = q1(conn, "SELECT COUNT(*) FROM files")
    print(f"Candidates: {total}")
    print()
    print("=== Categories ===")
    for cat, n in conn.execute(
            "SELECT category, COUNT(*) FROM files GROUP BY category ORDER BY 2 DESC"):
        print(f"  {cat:36s} {n:6d}")
    print()
    print("=== Out-of-scope would-be ===")
    for cat, n in conn.execute(
            "SELECT would_be, COUNT(*) FROM files WHERE would_be IS NOT NULL "
            "GROUP BY would_be ORDER BY 2 DESC"):
        print(f"  {cat:36s} {n:6d}")
    conn.close()


def cmd_query(args):
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(args.sql).fetchall()
        if not rows:
            print("(no results)")
            return
        keys = rows[0].keys()
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


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description='WPT corpus coverage analyzer')
    sub = parser.add_subparsers(dest='command')

    sub.add_parser('scan', help='Full-tree scan into coverage.db')
    sub.add_parser('validate', help='Check included set against classification.json')
    sub.add_parser('report', help='Generate COVERAGE.md + coverage-summary.json')
    sub.add_parser('summary', help='Print category breakdown')
    p_query = sub.add_parser('query', help='Run arbitrary SQL')
    p_query.add_argument('sql', help='SQL query to execute')

    args = parser.parse_args()
    commands = {
        'scan': cmd_scan,
        'validate': cmd_validate,
        'report': cmd_report,
        'summary': cmd_summary,
        'query': cmd_query,
    }
    if args.command is None:
        parser.print_help()
        sys.exit(1)
    commands[args.command](args)


if __name__ == '__main__':
    main()

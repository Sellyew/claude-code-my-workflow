#!/usr/bin/env bash
#
# Nightly reproducibility-drift check (cron-able; no Claude/auth needed).
#
# A thin LOCAL equivalent of the "Reproducibility drift" Routine in
# .claude/references/scheduled-routines.md, for users who prefer a machine
# cron over a managed Routine. It does NOT re-run analysis — it flags
# passport claims whose source_file / output_file, OR any file declared as a
# display in appears_in, is newer than the claim's last_verified_on (i.e. the
# number on disk may have moved, or two artifacts showing it may have fallen
# out of step, since it was last checked). Exits 1 if any claim is stale, so
# cron can email you.
#
# For the full re-audit, run /audit-reproducibility inside Claude Code (or
# prefer the managed Routine, which survives a closed laptop).
#
# Usage:  ./scripts/nightly-repro-check.sh   (run from the repo root or via cron)
#
set -uo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || exit 2

python3 - "$REPO_ROOT" <<'PY'
import sys, re, pathlib, datetime
root = pathlib.Path(sys.argv[1])
pdir = root / "quality_reports" / "passports"
if not pdir.is_dir():
    print("no quality_reports/passports/ — nothing to check"); sys.exit(0)

def parse_iso(s):
    s = s.strip().strip('"').strip("'")
    date_only = ("T" not in s) and (":" not in s)   # e.g. "2026-06-01"
    try:
        dt = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
        if date_only:                                # treat as END of that day so a
            dt = dt.replace(hour=23, minute=59, second=59)  # same-day edit isn't STALE
        return dt.timestamp()
    except Exception:
        return None

stale = []
for pf in sorted(pdir.glob("*.yaml")):
    lines = pf.read_text(errors="replace").splitlines()
    cur = {}
    def flush(c):
        lv = c.get("last_verified_on")
        if lv is None:
            return
        # The two provenance files PLUS every declared display: a touched deck or
        # supplement is as much a reason to re-check as a touched script — it is
        # the edit that puts two displays of one number out of step.
        seen = set()
        for f in [c.get("source_file"), c.get("output_file"), *c.get("displays", [])]:
            if not f or f in seen:
                continue
            seen.add(f)
            p = root / f
            try:
                if p.exists() and p.stat().st_mtime > lv:
                    stale.append(f"{pf.name}: {c.get('id','?')} — {f} newer than last_verified_on")
            except Exception:
                pass
    for ln in lines:
        m = re.match(r"\s*-\s*id:\s*(.+)", ln)
        if m:
            flush(cur); cur = {"id": m.group(1).strip()}
            continue
        # `- path:` is an appears_in display entry — several per claim is normal.
        m = re.match(r"\s*-?\s*(source_file|output_file|path|last_verified_on):\s*(.+)", ln)
        if m:
            k = m.group(1)
            v = re.sub(r"\s+#.*$", "", m.group(2)).strip().strip("\"'")
            if k == "last_verified_on":
                cur[k] = parse_iso(v)
            elif k == "path":
                cur.setdefault("displays", []).append(v)
            else:
                cur[k] = v
    flush(cur)

if stale:
    print("STALE claims (re-run /audit-reproducibility):")
    for s in stale: print("  " + s)
    sys.exit(1)
print("All tracked claims fresh (no source/output/display newer than last_verified_on).")
PY

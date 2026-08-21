#!/usr/bin/env python3
"""Scan for stale recommendations and drift the other gates cannot see.

The other gates check that surfaces agree WITH EACH OTHER. This one checks for
claims that were true once and are not any more, plus source/render divergence.

Exit: 0 clean, 1 stale content found, 2 internal error.
"""
import re, os, sys, glob, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# defect-library.md is a CATALOGUE of anti-patterns to seed — it contains them by design.
SKIP = re.compile(r'(^|/)(CHANGELOG\.md|defect-library\.md|\.git/|node_modules/|quality_reports/)')

def surfaces():
    out = []
    for pat in ["*.md", ".claude/**/*.md", "templates/**/*.md", "guide/*.qmd", "docs/*.html", ".github/**/*.md"]:
        out += glob.glob(os.path.join(ROOT, pat), recursive=True)
    return [p for p in sorted(set(out)) if not SKIP.search(os.path.relpath(p, ROOT))]

# (id, description, regex, allow-marker regex or None)
CHECKS = [
 ("STALE-TOOL", "names `Task` as the subagent tool (it is `Agent`)",
  r'via\s+`?Task`?\b|`Task`\s+subagent|spawn\w*\s+[^.\n]{0,30}\bvia\s+Task\b', r'legacy|prior|historical|alias|renamed|model-allow'),
 ("STALE-AUTOMODE", "describes auto mode as plan-gated (it is the Pro/Max/Team default since 2026-08-14)",
  r'auto mode\s+(requires|needs)\s+(Team|Enterprise)|rolling out to Max', r'UPDATED|no longer|was\b'),
 ("STALE-SUPERLATIVE", "unfalsifiable product claim",
  r'\bthe only (public )?(workflow|template|repo)\b|\bnobody else (has|can)\b|\bbest-in-class\b|\bthe first (public )?workflow\b', r'Banned|never claim|Seed|seed|anti-pattern|example of'),
 ("STALE-BLOCKER", "cites a closed issue as an open blocker",
  r'blocked (on|by) .{0,40}#11278|#11278.{0,40}(blocker|quirk)', r'UNBLOCKED|closed'),
]

def main():
    files = surfaces()
    hits = []
    for f in files:
        rel = os.path.relpath(f, ROOT)
        try: text = open(f, encoding="utf-8", errors="ignore").read()
        except Exception: continue
        for cid, desc, pat, allow in CHECKS:
            for i, line in enumerate(text.split("\n"), 1):
                if re.search(pat, line, re.I):
                    if allow and re.search(allow, line, re.I): continue
                    hits.append((cid, rel, i, desc, line.strip()[:90]))

    # source vs rendered divergence.
    #
    # NOT by mtime: git does not preserve timestamps, so on a fresh clone or a
    # detached worktree the checkout order decides which file looks newer. That
    # made this gate fail spuriously for every first-time forker and in CI.
    # (Codex review, PR #140 — confirmed by reproducing it in a fresh worktree.)
    #
    # Instead: compare a fingerprint of the SOURCE against the fingerprint the
    # last render recorded. Content, not clock.
    render = []
    for src, out in [("guide/workflow-guide.qmd", "guide/workflow-guide.html"),
                     ("guide/workflow-guide.qmd", "docs/workflow-guide.html")]:
        s_path, o_path = os.path.join(ROOT, src), os.path.join(ROOT, out)
        if not (os.path.exists(s_path) and os.path.exists(o_path)):
            continue
        import hashlib
        src_hash = hashlib.sha256(open(s_path, "rb").read()).hexdigest()[:16]
        stamp = os.path.join(ROOT, ".render-stamp")
        recorded = {}
        if os.path.exists(stamp):
            for line in open(stamp):
                if ":" in line:
                    k, v = line.strip().split(":", 1)
                    recorded[k] = v
        if recorded.get(out) != src_hash:
            render.append(f"{out} was not rendered from the current {src} "
                          f"(source {src_hash}, stamp {recorded.get(out, 'none')}) — "
                          f"re-render: cd guide && quarto render workflow-guide.qmd && "
                          f"./scripts/stamp-render.sh")

    # currency expiry — a verified_on date that has aged out
    expired = []
    mv = os.path.join(ROOT, ".claude/references/model-versions.md")
    if os.path.exists(mv):
        t = open(mv).read()
        m = re.search(r'\*\*Expires:\*\*\s*(\d{4}-\d{2}-\d{2})', t)
        if m:
            today = subprocess.run(["date","+%Y-%m-%d"],capture_output=True,text=True).stdout.strip()
            if today > m.group(1):
                expired.append(f"model-versions.md expired {m.group(1)} (today {today}) — re-verify against the docs")

    print(f"check-staleness: {len(files)} surfaces scanned")
    bad = hits or render or expired
    for cid, rel, i, desc, line in hits: print(f"  [{cid}] {rel}:{i}  {desc}\n      {line}")
    for r in render:  print(f"  [STALE-RENDER] {r}")
    for e in expired: print(f"  [STALE-EXPIRY] {e}")
    if not bad: print("No stale recommendations, no source/render divergence, no expired currency claims.")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())

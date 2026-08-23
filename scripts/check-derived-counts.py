#!/usr/bin/env python3
"""Verify enumerable claims that surface-sync does not cover.

surface-sync checks skills/agents/rules/hooks. This checks the OTHER numbers a
reader might rely on — journal profiles, workflow patterns, TikZ snippets,
translation phases, review passes — each counted from its own source of truth.

Exit: 0 all claims match, 1 mismatch, 2 internal error.
"""
import re, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def read(p):
    try: return open(os.path.join(ROOT, p), encoding="utf-8", errors="ignore").read()
    except FileNotFoundError: return ""

def n_econ_journals():
    t = read(".claude/references/journal-profiles.md")
    seg = re.search(r'^## Econ Top.*?(?=^## (?!#)|\Z)', t, re.S | re.M)
    return len(re.findall(r'^### ', seg.group(0), re.M)) if seg else 0

def n_patterns():
    return len(set(re.findall(r'^#{2,3} Pattern (\d+)', read("guide/workflow-guide.qmd"), re.M)))

def n_tikz():
    d = os.path.join(ROOT, "templates", "tikz-snippets")
    return len([f for f in os.listdir(d) if f.endswith(".tex")]) if os.path.isdir(d) else 0

def n_translate_phases():
    ph = set(re.findall(r'^#{2,4} Phase (\d+)', read(".claude/skills/translate-to-quarto/SKILL.md"), re.M))
    return len(ph - {"0"})            # Phase 0 is pre-flight, not a translation phase

def n_gates():
    t = read("scripts/backtest.sh")
    n = len(re.findall(r'^run "', t, re.M))
    return n

def n_seven_pass():
    t = read(".claude/skills/seven-pass-review/SKILL.md")
    return len(set(re.findall(r'^\| (\d) \|', t, re.M)))

# (label, claimed-value regex, surfaces to scan, actual count)
CHECKS = [
    # Phrasings verified against the actual surfaces 2026-08-21. If you reword a
    # claim, update the pattern here too — an unmatched pattern reports nothing,
    # which is indistinguishable from a claim that is correct.
    ("econ journal profiles", r'top-(\d+) journal profiles',      ["README.md", "guide/workflow-guide.qmd"], n_econ_journals()),
    ("TikZ snippets",         r'(\d+) production-ready',       ["guide/workflow-guide.qmd"], n_tikz()),
    ("translation phases",    r'(\d+) translation phases',       ["README.md", "guide/workflow-guide.qmd"], n_translate_phases()),
    # The 7-vs-8 drift cluster: seven separate surfaces claimed the wrong gate
    # count after gate 8 landed. Counted from backtest.sh itself.
    ("backtest gates",        r'(?i)\b(one|two|three|four|five|six|seven|eight|nine|ten|\d+) gates\b', ["README.md", "docs/index.html", "CLAUDE.md", "guide/workflow-guide.qmd", ".claude/skills/vaccinate/evals/README.md"], n_gates()),
    ("seven-pass lenses",     r'(\d+) forked subagents',         [".claude/skills/seven-pass-review/SKILL.md"], n_seven_pass()),
]

def main():
    bad = []
    print("check-derived-counts: enumerable claims outside surface-sync's scope")
    for label, pat, surfaces, actual in CHECKS:
        found = False
        for f in surfaces:
            for m in re.finditer(pat, read(f)):
                found = True
                g = m.group(1)
                WORDS = {"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,
                         "seven":7,"eight":8,"nine":9,"ten":10}
                claimed = WORDS.get(g.lower(), None) if not g.isdigit() else int(g)
                if claimed is None: continue
                ok = claimed == actual
                print(f"  {label:<22} {f:<28} claims {claimed:>3}  actual {actual:>3}  {'ok' if ok else 'MISMATCH'}")
                if not ok:
                    bad.append(f"{f}: claims {claimed} {label}, actual {actual}")
        if not found:
            print(f"  {label:<22} {'(no claim found)':<28} actual {actual:>3}  —")
    # patterns are sequential-by-construction: 1..N with no gaps
    ids = sorted(int(x) for x in set(re.findall(r'^#{2,3} Pattern (\d+)', read("guide/workflow-guide.qmd"), re.M)))
    if ids and ids != list(range(1, len(ids) + 1)):
        bad.append(f"workflow patterns are not sequential: {ids}")
        print(f"  workflow patterns      NOT SEQUENTIAL: {ids}")
    else:
        print(f"  workflow patterns      sequential 1..{len(ids)}  ok")
    if bad:
        print(f"\n{len(bad)} MISMATCH(ES):")
        for b in bad: print(f"  {b}")
        return 1
    print("\nAll derived counts match their source of truth.")
    return 0

if __name__ == "__main__":
    sys.exit(main())

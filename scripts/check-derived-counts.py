#!/usr/bin/env python3
"""Verify enumerable claims that surface-sync does not cover.

surface-sync checks skills/agents/rules/hooks. This checks the OTHER numbers a
reader might rely on — journal profiles, workflow patterns, TikZ snippets,
translation phases, review passes — each counted from its own source of truth.

Exit: 0 all claims match, 1 mismatch, 2 internal error.
"""
import glob, re, os, sys
from collections import namedtuple

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

# --- release-inventory counts -------------------------------------------------
#
# These MIRROR check-surface-sync.py's GROUND_TRUTH definitions exactly — skills
# are `*/SKILL.md`, agents/rules are `*.md`, hooks are `*.py` + `*.sh` — so the
# two gates can never disagree about what a "skill" or a "hook" is. If you change
# a definition there, change it here in the same commit.
def _glob_count(pat):
    return len(glob.glob(os.path.join(ROOT, pat)))

def n_skills(): return _glob_count(".claude/skills/*/SKILL.md")
def n_agents(): return _glob_count(".claude/agents/*.md")
def n_rules():  return _glob_count(".claude/rules/*.md")
def n_hooks():  return _glob_count(".claude/hooks/*.py") + _glob_count(".claude/hooks/*.sh")


def changelog_current_release():
    """The text under the TOPMOST `## v…` heading of CHANGELOG.md, and nothing else.

    WHY THIS IS SCOPED, and not simply "scan CHANGELOG.md" the way every other
    row scans a whole file: the changelog keeps the `**Inventory at release: …**`
    line of EVERY past release. Those numbers were TRUE at their release and are
    a historical record — `.claude/references/audit-pet-peeves.md` #12
    ("historical CHANGELOG entries — do not update") is why CHANGELOG.md is not a
    check-surface-sync surface at all. Comparing them against today's disk would
    turn a CORRECT record red, and the only way to quiet that red would be to
    falsify or delete the history. So the view handed to the gate ends at the
    next `## ` heading: exactly ONE inventory line — the current release's — is
    ever compared, and v2.5.0's `36 rules, 7 hooks` (correct then, wrong now) is
    invisible to it.

    The window MOVES on its own. When the next release heading is added above,
    the line this gate checks becomes that release's, and the previous one
    becomes history — on the same commit, with no gate change and no exclusion
    list to maintain. And because these rows' surface is REQUIRED, deleting or
    rewording the current inventory line does not silently drop coverage: the
    row reports NO CLAIM MATCHED and the gate goes red.
    """
    m = re.search(r'^## v[^\n]*\n(.*?)(?=^## |\Z)', read("CHANGELOG.md"), re.S | re.M)
    return m.group(1) if m else ""

def n_hook_battery_cases():
    # The battery prints "ALL PASS (N cases)" where N = TOTAL = PASS + FAIL —
    # the `TOTAL=$((PASS + FAIL))` roll-up in the final summary block of
    # scripts/hook-battery.sh (find it with `grep -n 'ALL PASS'`; it is cited
    # by name, not by line number, because line numbers rot as the battery
    # grows — this comment previously said "line ~276", which by round 7
    # pointed into an unrelated fixture comment). Every case runs exactly one
    # expect_ helper (expect_deny / expect_silent / expect_contains). Count
    # those CALL sites — the SAME tokens the battery itself counts — so this
    # gate and the battery's printed N can never disagree. A call is the helper
    # name followed by whitespace (`expect_deny   "a1..."`); a definition is the
    # name followed by `()` (`expect_deny() {`), so the `[ \t]` after the name
    # excludes the three definitions.
    t = read("scripts/hook-battery.sh")
    return len(re.findall(r'^[ \t]*expect_(?:deny|silent|contains)[ \t]', t, re.M))


def _battery_sections():
    """hook-battery.sh split by its own `# ── (x) ` section banners, so a count
    can be taken PER GUARD as well as for the whole battery."""
    parts = re.split(r'^# ── \((\w)\) ', read("scripts/hook-battery.sh"), flags=re.M)
    secs = {}
    for i in range(1, len(parts) - 1, 2):
        secs[parts[i]] = secs.get(parts[i], "") + parts[i + 1]
    return secs

def n_battery_named(letters):
    # The LEDGER's grading-the-grader row records, per guard, how many cases go
    # red when that guard is replaced by an always-allow stub. A stub allows
    # everything, so exactly the expect_deny / expect_contains cases in that
    # guard's sections fail — count those call sites. Until 2026-08-23 these
    # three numbers (17 / 13 / 2) were the ledger's own, ungated: planting 99 in
    # each left every gate green, which is the r7 defect one document over.
    secs = _battery_sections()
    body = "".join(secs.get(l, "") for l in letters)
    return len(re.findall(r'^[ \t]*expect_(?:deny|contains)[ \t]', body, re.M))


def n_laws():
    # Each law in research-agent-laws.md opens a paragraph as **N. Title.**
    # Counting the numbered openers keeps CLAUDE.md's "N laws" honest: the
    # count was hand-edited 17 -> 21 once, with nothing to catch a wrong value.
    t = read(".claude/references/research-agent-laws.md")
    return len(re.findall(r'^\*\*(\d+)\.', t, re.M))

# English number words 0-99, so a spelled-out count ("Twelve cases",
# "Twenty-two cases") is compared as a number like a digit claim.
_ONES = {"zero":0,"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,
         "eight":8,"nine":9,"ten":10,"eleven":11,"twelve":12,"thirteen":13,
         "fourteen":14,"fifteen":15,"sixteen":16,"seventeen":17,"eighteen":18,
         "nineteen":19}
_TENS = {"twenty":20,"thirty":30,"forty":40,"fifty":50,"sixty":60,"seventy":70,
         "eighty":80,"ninety":90}
def words_to_int(tok):
    if tok is None: return None
    tok = tok.strip().lower()
    if tok.isdigit(): return int(tok)
    if tok in _ONES: return _ONES[tok]
    if tok in _TENS: return _TENS[tok]
    if "-" in tok:
        a, _, b = tok.partition("-")
        if a in _TENS and b in _ONES and _ONES[b] < 10:
            return _TENS[a] + _ONES[b]
    return None

def n_seven_pass():
    t = read(".claude/skills/seven-pass-review/SKILL.md")
    return len(set(re.findall(r'^\| (\d) \|', t, re.M)))

# --- Per-surface expectation --------------------------------------------------
#
# A row's `surfaces` entry is EITHER a bare path string — meaning this surface is
# REQUIRED to carry the claim, and a surface that stops matching is a gate
# failure — OR `OPT(path, why)`, meaning this surface is scanned but may
# legitimately make no such claim, with the reason written down.
#
# Why explicit expectation, and not inference: until 2026-08-23 `found` was ONE
# boolean per ROW, so the round-7 UNGATED failure fired only when EVERY surface
# in a row stopped matching. Reword the claim on one surface of a multi-surface
# row and the row stayed green on its sibling — the surface silently left
# coverage while the output still read like a pass ("hook battery cases
# CHANGELOG.md claims 51 actual 51 ok"). That is the r7 defect one dimension
# over. The obvious repair — "every declared surface must match" — is wrong on
# its own, because three declared surfaces legitimately carry no claim of their
# row's kind today (see the OPT reasons below); it would have made the gate red
# on a correct repo, and the fix for that noise would have been to DELETE those
# surfaces from the row, which is exactly how coverage disappears quietly.
#
# So the expectation is DECLARED, never guessed:
#   * a REQUIRED surface that matches nothing            -> UNGATED failure (red)
#   * an OPT surface that matches nothing                -> printed as
#     "no claim (optional: <why>)" — visible in the log, not silent
#   * an OPT surface that DOES match                     -> value-checked like
#     any other, so coverage can only grow by accident, never shrink
#   * a row with NO required surface at all              -> failure, because
#     such a row can never go red and is not a gate
# Demoting a REQUIRED surface to OPT therefore costs a diff with a written
# reason in it — a reviewable act — instead of an invisible non-match.
OPT = namedtuple("OPT", "path why")

# A third surface form: a SECTION of a file rather than the whole file. `label`
# is what the log prints, `text` is the already-extracted view the pattern is
# matched against. It is REQUIRED like a bare path — a section that stops
# carrying its claim is an UNGATED failure, same as a file that stops carrying
# one. Used for the CHANGELOG's current-release inventory line, where scanning
# the whole file would compare CORRECT historical entries against today's disk
# (see changelog_current_release() for the full reasoning).
SEC = namedtuple("SEC", "label text")

def _surface_path(s):
    if isinstance(s, SEC):
        return s.label
    return s.path if isinstance(s, OPT) else s

def _surface_text(s):
    return s.text if isinstance(s, SEC) else read(_surface_path(s))

def _surface_required(s):
    return not isinstance(s, OPT)

# Extracted once, so every release-inventory row below reads the SAME window.
_CL_CURRENT = changelog_current_release()

# (label, claimed-value regex, surfaces to scan, actual count)
CHECKS = [
    # Phrasings verified against the actual surfaces 2026-08-21. If you reword a
    # claim, update the pattern here too — an unmatched pattern reports nothing,
    # which is indistinguishable from a claim that is correct.
    ("econ journal profiles", r'top-(\d+) journal profiles',      ["README.md", "guide/workflow-guide.qmd"], n_econ_journals()),
    ("TikZ snippets",         r'(\d+) production-ready',       ["guide/workflow-guide.qmd"], n_tikz()),
    # guide/workflow-guide.qmd shows the translate-to-quarto phases as an ASCII
    # tree ("Phase 1-3 ... Phase 10-11") and never states an "N translation
    # phases" total, so it is scanned but not required to match.
    ("translation phases",    r'(\d+) translation phases',       ["README.md", OPT("guide/workflow-guide.qmd", "shows the phases as a tree, states no total")], n_translate_phases()),
    # The 7-vs-8 drift cluster: seven separate surfaces claimed the wrong gate
    # count after gate 8 landed. Counted from backtest.sh itself.
    # CLAUDE.md names the gate suite ("the full backtest gate suite") but states
    # no count; the vaccinate evals README says "the gates in ./scripts/backtest.sh"
    # for the same reason. Both are scanned so a count APPEARING there is caught,
    # neither is required to carry one.
    # r10: the noun is `(?:gates|checkers)`, not `gates` alone. README.md states
    # the gate-suite size TWICE — "ten gates" at line 79 and, above the fold in
    # the very first paragraph a prospective forker reads, "`./scripts/backtest.sh`
    # — 10 checkers". Only the first phrasing matched, and because `found` is per
    # SURFACE (not per phrasing) the sibling match kept the row green, so no
    # NO CLAIM MATCHED fired either: a planted-lie sweep set the second instance
    # to "99 checkers" and ./scripts/backtest.sh still exited 0. That number had
    # ALREADY drifted once — it was hand-repaired 8 -> 10 on this branch, the
    # exact pattern the "research-agent laws" row below was added for. Widening
    # the noun converts a second phrasing into coverage instead of deleting it.
    # Verified 2026-08-23: `\b<number> checkers?\b` occurs at exactly ONE site in
    # the repo (README.md:17), so the alternative adds coverage, not false hits.
    # r12: `scripts/backtest.sh` ITSELF is a surface. Its header comment states
    # the suite size ("Ten gates:") 45 lines above the `run "…"` block the count
    # is derived from, it was hand-edited `Eight gates:` -> `Ten gates:` on this
    # branch, and it was the LAST live gate-count claim in the repo that no row
    # covered: a planted-lie sweep seeding "ninety-nine gates:" at line 5 left
    # every gate at exit 0. The file being both the claim and the source of
    # truth is fine and was checked, not assumed — the pattern matches at
    # exactly ONE site in it (the header), because the enumeration below the
    # header numbers its gates `1.`…`10.` rather than restating a total, and
    # `n_gates()` counts `^run "` lines, which the pattern cannot match.
    ("backtest gates",        r'(?i)\b(one|two|three|four|five|six|seven|eight|nine|ten|\d+) (?:gates|checkers)\b', ["README.md", "docs/index.html", OPT("CLAUDE.md", "names the gate suite, states no count"), "guide/workflow-guide.qmd", OPT(".claude/skills/vaccinate/evals/README.md", "refers to the suite by path, states no count"), ".claude/skills/commit/SKILL.md", ".github/CONTRIBUTING.md", "scripts/backtest.sh"], n_gates()),
    # CLAUDE.md's law count was hand-edited 17 -> 21 and nothing recomputed it,
    # so "99 laws" would have left every gate green. Counted from the laws file.
    ("research-agent laws",   r'(\d+) laws\b',                   ["CLAUDE.md"], n_laws()),
    ("seven-pass lenses",     r'(\d+) forked subagents',         [".claude/skills/seven-pass-review/SKILL.md"], n_seven_pass()),
    # The hook-battery case count drifted twice (12→16→…) because prose was
    # edited in parallel with case additions. Anchored on the vignette's own
    # ", about a second" tail so it matches ONLY the battery claim (not generic
    # "cases"), and counted from the battery's own expect_ call sites.
    # Tail alternatives, not one literal: the phrasing was reworded during v2.6
    # (the runtime claim "about a second" stopped being true as the battery grew)
    # and the single-literal anchor silently stopped matching — the gate printed
    # "(no claim found)" and stayed green, which is why an unmatched pattern is
    # now a FAILURE (see main()).
    ("hook battery cases",    r'(\d+|[A-Za-z]+(?:-[A-Za-z]+)?) cases, (?:about a second|seconds to run|and it finishes in seconds)', ["CHANGELOG.md", "guide/workflow-guide.qmd"], n_hook_battery_cases()),
    # The QUALIFICATION LEDGER states the same number in its own phrasing —
    # "(46 cases, exit 0)" in the Reproduction paragraph and "(46/46 cases, exit
    # 0)" in the grading-the-grader row — and until 2026-08-23 NEITHER was a
    # declared surface of any row. A planted-lie sweep confirmed it: replacing
    # each with 99 left check-surface-sync, check-derived-counts, check-staleness
    # and check-ledger-coverage all at exit 0, while the same sweep caught all
    # 24 other count-claim sites in the repo. That is the failure this ledger
    # exists to prevent, sitting in the ledger: a maintainer re-qualifying the
    # guards runs the battery, sees a different N, and cannot tell whether a
    # case was added or whether the recall DENOMINATOR was never updated.
    ("battery cases (ledger)", r'(\d+|[A-Za-z]+(?:-[A-Za-z]+)?) cases, exit 0',    ["quality_reports/qualification/LEDGER.md"], n_hook_battery_cases()),
    ("battery-named root-of-trust", r'`root-of-trust-guard\.py` \((\d+) cases named\)', ["quality_reports/qualification/LEDGER.md"], n_battery_named("a")),
    ("battery-named git-guardrails", r'`git-guardrails\.py` \((\d+) cases named\)',     ["quality_reports/qualification/LEDGER.md"], n_battery_named("bc")),
    ("battery-named claim-reconcile", r'`claim-reconcile\.py` \((\d+) cases named\)',   ["quality_reports/qualification/LEDGER.md"], n_battery_named("d")),
    # n_patterns() was COMPUTED (and printed as "sequential 1..N") but never
    # compared against the prose, so "Nineteen patterns is a reference shelf"
    # could go stale the moment Pattern 20 landed — sequentiality still passes
    # on 1..20. Anchored on the vignette's own "is a reference shelf" tail, and
    # the count is spelled out, which words_to_int already handles.
    ("workflow patterns",     r'(\d+|[A-Za-z]+(?:-[A-Za-z]+)?) patterns is a reference shelf', ["guide/workflow-guide.qmd", "docs/workflow-guide.html"], n_patterns()),
    # --- the current release's inventory line (r10) ---------------------------
    # CHANGELOG.md's `**Inventory at release: N skills, N agents, N rules,
    # N hooks, N gates**` publishes five counts of this repository's own
    # surfaces and NOT ONE of them was read by any gate: CHANGELOG.md is absent
    # from check-surface-sync's SURFACES (deliberately — see
    # changelog_current_release() for why), and no row here declared it for
    # skills/agents/rules/hooks/gates. A planted-lie sweep put 99 in each, one
    # at a time, and ./scripts/backtest.sh exited 0 every time.
    #
    # That is not hypothetical drift: on THIS branch alone the rules directory
    # went 36 -> 37, hooks 7 -> 8, and gates 8 -> 10 while the release notes were
    # being written. Once the heading below it is no longer the top one, the line
    # freezes as history — so a wrong number here becomes permanent.
    #
    # SCOPING: the surface is the CURRENT release section only, never the file.
    # Historical inventory lines (v2.5.0's `36 rules, 7 hooks`, v2.1.0's
    # `52 skills`) were correct at their release and must NOT be dragged to
    # today's values; they are outside the window and cannot go red. See
    # changelog_current_release().
    #
    # Anchored on "Inventory at release:" and confined to one line by `[^\n*]*?`,
    # which also stops at the closing `**` — so the trailing "(was 60 / 18 / 36 /
    # 7 / 8 at v2.5.0)" comparison, a deliberate historical statement about the
    # PREVIOUS release, is not matched either.
    ("release inventory skills", r'Inventory at release:[^\n*]*?(\d+) skills', [SEC("CHANGELOG.md (current release)", _CL_CURRENT)], n_skills()),
    ("release inventory agents", r'Inventory at release:[^\n*]*?(\d+) agents', [SEC("CHANGELOG.md (current release)", _CL_CURRENT)], n_agents()),
    ("release inventory rules",  r'Inventory at release:[^\n*]*?(\d+) rules',  [SEC("CHANGELOG.md (current release)", _CL_CURRENT)], n_rules()),
    ("release inventory hooks",  r'Inventory at release:[^\n*]*?(\d+) hooks',  [SEC("CHANGELOG.md (current release)", _CL_CURRENT)], n_hooks()),
    ("release inventory gates",  r'Inventory at release:[^\n*]*?(\d+) gates',  [SEC("CHANGELOG.md (current release)", _CL_CURRENT)], n_gates()),
]

def main():
    bad = []
    print("check-derived-counts: enumerable claims outside surface-sync's scope")
    for label, pat, surfaces, actual in CHECKS:
        # A row with no REQUIRED surface can never go red: every surface would be
        # free to drop its claim. Such a row is not a gate, so say so.
        if not any(_surface_required(s) for s in surfaces):
            print(f"  {label:<22} {'NO REQUIRED SURFACE':<28} actual {actual:>3}  UNGATED")
            bad.append(f"{label}: every declared surface is OPT, so this row can never "
                       f"fail — promote at least one surface to REQUIRED")
        for s in surfaces:
            f = _surface_path(s)
            found = False          # PER SURFACE, not per row (see OPT above)
            for m in re.finditer(pat, _surface_text(s)):
                found = True
                g = m.group(1)
                claimed = words_to_int(g)
                if claimed is None: continue
                ok = claimed == actual
                print(f"  {label:<22} {f:<28} claims {claimed:>3}  actual {actual:>3}  {'ok' if ok else 'MISMATCH'}")
                if not ok:
                    bad.append(f"{f}: claims {claimed} {label}, actual {actual}")
            if found:
                continue
            if _surface_required(s):
                # This surface is DECLARED to carry the claim. If the pattern now
                # matches nothing here, the claim was reworded or deleted and this
                # surface has left coverage — indistinguishable from a claim that
                # is correct, and exactly how a count drifts unnoticed. Fail
                # loudly, naming the file, even when a sibling surface still
                # matches and the row therefore "looks" checked.
                print(f"  {label:<22} {f:<28} {'NO CLAIM MATCHED':<18}  UNGATED")
                bad.append(f"{f}: the {label} pattern matched nothing there — the claim "
                           f"was reworded, so this surface is no longer checked "
                           f"(restore the phrasing, update the pattern, or mark the "
                           f"surface OPT with a reason)")
            else:
                print(f"  {label:<22} {f:<28} no claim (optional: {s.why})")
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

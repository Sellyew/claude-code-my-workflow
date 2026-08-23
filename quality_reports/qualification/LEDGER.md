# Qualification Ledger

Every check, gate, and review agent that is allowed to clear work must have a row here.
**A checker with no row is unqualified, and its green light means nothing.**

Written by `/vaccinate`. See [`verification-ladder.md`](../../.claude/references/verification-ladder.md) rung 0.

Verdicts: **PASS** (detects its named class at the stated threshold) · **FAIL** (misses it) ·
**BLOCKED** (could not be run — reason required; never record as PASS).

| Date | Target | Artifact | Defect classes | N | Recall | FPR | Baseline | Verdict |
|---|---|---|---|---|---|---|---|---|
| 2026-08-21 | `check-model-versions.sh` | `README.md` | T1 superseded-model-as-current | 1 | 1/1 | 0/0 on clean control | `grep -c "Opus 4.8"` also detects; gate's value is its allow-marker logic | **PASS** |
| 2026-08-21 | `check-model-versions.sh` (replicate — script unchanged since prior row, per `git log`) | `README.md` | T1, two flavors: superlative + version line · bare superseded version string, no superlative | 2 | 2/2, both localized to `README.md:442` | 0/0 on restored clean control | bare grep false-alarms on allow-marked historical mentions; gate's value remains SSoT-anchor + allow logic | **PASS** |
| 2026-08-21 | `check-skill-integrity.py` | `.claude/skills/capture-environment/SKILL.md` | T3 body invokes a tool absent from `allowed-tools` | 1 | 1/1 | 0/0 on clean control | none simpler (needs frontmatter↔body parse) | **PASS** |

| 2026-08-21 | `scripts/backtest.sh` (all 6 gates) | `README.md` | broken link · stale model · count drift · unfalsifiable superlative | 4 | **3/4** | 0/0 on clean control | n/a (composite) | **FAIL** → fixed, see next row |
| 2026-08-21 | `check-surface-sync.py` count patterns | `README.md` | template-verb count drift ("this template has N skills") | 3 | 3/3 | **0/3** on legitimate-prose controls ("start with 2-3 skills", "7 parallel agents", "clo-author ships 17 specialized agents") | bare `grep -c` would false-positive on all 3 controls | **PASS** |
| 2026-08-21 | `scripts/check-links.py` | `README.md`, `CLAUDE.md` | missing file · unresolvable heading anchor | 2 | 2/2 | 0/0 on clean control | none simpler (needs anchor slugging) | **PASS** |
| 2026-08-21 | `scripts/validate-findings.py` | synthetic findings array | wrapper-not-array · missing field · unknown field · bad enum · non-derived id · duplicate id · line 0 · malformed JSON | 8 | 8/8 | 0/1 (valid finding accepted) | none | **PASS** |

| 2026-08-21 | `scripts/backtest.sh` — **full stress test, all 7 gates** | `README.md`, `CLAUDE.md`, `docs/index.html`, `scripts/`, a skill | count drift (compound) · count drift (template verb) · superseded model · broken link · broken anchor · superlative · stale auto-mode claim · root scratch file · draft copy · undeclared tool | 10 | **10/10** | **0/1** on the clean-repo control | n/a (composite) | **PASS** |
| 2026-08-21 | `check-surface-sync.py` coverage of `docs/index.html` | landing page | count drift on the published page | 1 | 1/1 | 0/0 | n/a | **PASS** (see note) |

## Harness qualification (2026-08-21)

The eval harness is itself a check, so it had to be qualified before any result it produces
counts. Three defects were found by running it, and one of them made every prior number
meaningless:

| Defect | How it presented | Fix |
|---|---|---|
| N=1 replicate | same case scored 3/3 and then 1/3 ten minutes later | default N=3 + a variance gate that exits 3 when sd > 0.5 |
| `nottrigger` written backwards | scored 1/1 whatever happened | `nottrigger-*` cases now invert the assertion |
| single-substring grading | correct answers phrased differently scored as misses | assertions list alternatives; any one counts |
| **the manipulation never happened** | **`--settings skillOverrides`, `Skill(name)` deny rules, and `--disallowedTools Skill` all FAIL to remove a project skill in headless mode.** Both arms had the skill. A clean, low-variance, entirely false result was about to be recorded here. | `--setting-sources user` verified to actually drop project skills; a **mandatory manipulation check now aborts the run** when both arms look identical |

> **The variance gate measured precision, not validity.** Three identical measurements of the
> wrong thing are perfectly precise. Only the positive control — *did the manipulation take?* —
> catches that, and it is now the first thing the harness runs.

| 2026-08-21 | **`scripts/run-skill-eval.sh` (the harness itself)** | negative control: unrelated question | harness must NOT invent a benefit | 1 case × 3 reps | delta **0** (3/3 vs 3/3, sd 0.00) | 0 — no false benefit | n/a | **PASS** |
| 2026-08-21 | **`scripts/run-skill-eval.sh` (the harness itself)** | positive control: a fact present only in `defect-library.md` | harness must detect a real benefit | 1 case × 3 reps | **+2** (6/6 vs 4/6, sd 0.00) | — | baseline cannot know the fact | **PASS** |
| 2026-08-21 | **manipulation check** | skill visibility probe | did the with/without manipulation take? | 2 probes | with=1, without=0 | — | — | **PASS** |

| 2026-08-21 | `check-repo-hygiene.py` | tracked tree | root scratch · `_old` copy · numbered duplicate (sibling) · `_v2` filename · tracked `.aux` · unexpected top-level dir | 6 | 6/6 | **0/2** on controls (numbered pipeline stage; numbered file with no sibling) | `git status` alone sees none of these | **PASS** |
| 2026-08-21 | `check-derived-counts.py` | README/guide/index | wrong journal count · wrong phase count · wrong snippet count · wrong gate count | 4 | 4/4 | 0/0 | bare grep cannot map claim→source-of-truth | **PASS** |
| 2026-08-22 | `check-spec-conformance.py` | temp skill | empty `description:` (the greedy-regex bug had masked it) | 1 | 1/1 | 0/0 on clean control | — | **PASS** |
| 2026-08-21 | `check-staleness.py` | README, guide/docs HTML | stale auto-mode claim · unfalsifiable superlative · hand-edited render · source-without-render · expired SSoT (date-shimmed) | 5 | 5/5 | 0/0 | mtime comparison (the approach it replaced) fails on fresh clones | **PASS** |
| 2026-08-21 | `quality_score.py` | `.qmd` | broken R chunk + placeholder text (auto-fail path) | 1 | 1/1 (exit 2) | 0/1 — clean control scored 100/exit 0 | — | **PASS** |

## Skill evals — not yet run

Distinct from gate qualification. `/vaccinate` asks *can this checker detect a planted defect?*
Evals ask *does this skill produce better work than not having it?* A skill can pass evals and
still be a useless reviewer — well-formed, plausible findings that miss real defects. Run both.

**No skill in this template has been eval'd.** Method and priority order:
[`.claude/skills/vaccinate/evals/README.md`](../../.claude/skills/vaccinate/evals/README.md).

## Not yet qualified

These are relied upon and have **never been measured**. Until they have a row, treat their
output as unverified.

| Target | Why it matters |
|---|---|
| `/review-paper --peer` | used for submission decisions |
| `claim-verifier` (CoVe) | HIGH-WARN gate-refuses `/commit` |
| `/audit-reproducibility` | gates the replication package |
| `/seven-pass-review` | submission-readiness |
| the 18-agent review fleet | every fan-out review |

## Notes

- A **PASS at one difficulty is not a PASS at another.** Record the threshold.
- **Re-qualify after changing a checker.** A modified gate is unqualified.
- A **bad seed** (one the artifact already permits) produces a correct "pass" and looks like a
  broken gate. Verify the seed creates a real violation before recording a FAIL.

> **A qualification run found a real blind spot (2026-08-21).** Seeding "This template has 99
> skills." into `README.md` left every gate **green** — the count patterns are deliberately
> compound (they require several categories on one line) to avoid false-positives on prose like
> "start with 2-3 skills", and a bare count carrying only a template verb slipped between them.
> Fixed by adding template-verb patterns, then re-qualified **in both directions**: 3/3 seeded
> drifts caught, 0/3 false alarms on legitimate prose. **This is the whole argument for rung 0 —
> the gate had been green and wrong, and only a seeded defect could tell the difference.**

> **A rewrite silently removed a surface from coverage (2026-08-21).** Rebuilding
> `docs/index.html` around persona paths replaced its compound count phrasing with separate
> bulleted lines. Every gate stayed green — because the page was no longer being *checked*.
> Seeding a wrong count into the page proved it: exit 0, uncovered. Fixed by restoring one
> compound assertion line, then re-proved: seeded drift now caught.
>
> **The lesson generalises beyond counts.** Improving a surface can remove it from gate
> coverage without any gate going red, because a gate that matches nothing reports nothing.
> After editing any checked surface, seed a defect into *that surface* and confirm it is still
> seen. Total assertions went 29 → 34 across this release; a falling number is the signal to
> look for.

## New staleness checks from the Oracle-review adoption (2026-08-22)

| Check | Seeded defect | Red? | Control | Green? |
|---|---|---|---|---|
| staleness: guide-version parity | guide frontmatter set to 9.9.9 vs CHANGELOG v2.5.0 | yes — STALE-VERSION, exit 1 | matching 2.5.0 | yes |
| staleness: reversed injection syntax | seeded `` `!git status --short` `` into skill-template | yes — BAD-INJECT-SYNTAX, exit 1 | clean tree incl. diagnose's legitimate `` `!anyNA(w)` `` (guard: parenthesized R negations and `/shell/` paths excluded) | yes — no false alarm |

## Harness re-qualification after Codex round 3 (2026-08-22)

Three confirmed findings (PR #140 round 3) changed the harness and validator; each fix was
re-qualified with a seeded defect AND a clean control (an unqualified check is none):

| Check | Seeded defect | Red? | Control | Green? |
|---|---|---|---|---|
| eval harness: invocation guard | PATH shim forces `claude` to exit 124 on per-case calls (smoke + manipulation pass) | yes — retries once, then ABORT exit 2, no report | same shim answering all calls | yes — completes, exit 0 |
| eval harness: variance gate, binary cases | 1-assertion case with hits [0,1,1] (pstdev 0.47 < old 0.5 threshold) | yes — flagged, exit 3 | stable [1,1,1]; and multi-assert [0,3,0] still exits 3 | yes — exit 0 / exit 3 |
| validate-findings: non-string id | finding with `"id": 1` | yes — clean diagnostic, exit 1 (previously TypeError crash) | `[]` smoke | yes — exit 0 |

## Skill eval results (2026-08-22, final harness: sandboxed, behavioral manipulation check, N=3)

Every run passed the behavioral manipulation check (with-arm retrieved the skill-only marker;
without-arm demonstrably could not). Raw jsonl committed under `evals/<skill>/`.

| Skill | Cases | With | Without | Delta | Verdict |
|---|---|---|---|---|---|
| `did-event-study` *(skill removed 2026-08-22 — owner veto: unvetted methodology in the owner's own field; row kept as the measurement record)* | never-reimplement | **3/3** (sd 0.00) | **0/3** (sd 0.00) | **+3** | **Clear benefit.** Baseline complied with a "reimplement the estimator from scratch" request in 3 of 3 replicates — the same behaviour that once wrote a from-scratch ATT(g,t) into this repo. The skill refused every time. |
| `verify-claims` | fresh-context-independence | 2/3 (sd 0.47) | 0/3 (sd 0.00) | **+2** | Benefit, borderline stability — the with-arm hit the fresh-context doctrine in 2 of 3 replicates. Under the sd≤0.5 gate, but barely; more cases wanted before leaning on it. |
| `audit-reproducibility` | manuscript-not-oracle · tolerance-before-comparison | 8/9 | 7/9 | **+1** | Split: the distinctive doctrine ("the manuscript is not the oracle") is +2; the tolerance case is −1 because **baseline already knows** to fix tolerances first. |
| `challenge` *(both DiD cases removed 2026-08-22 with the DiD-content veto; row kept as the measurement record)* | estimand-fork · pretrend | 9/9 | 8/9 | **+1** | The pre-trends case is 6/6 in BOTH arms — baseline already knows flat pre-trends are not evidence and names honest DiD. The estimand fork is +1. The skill's marginal value is *procedure* (grid, ledger, budget), which one-shot Q&A cannot measure. |
| `vaccinate` | 3 cases | 18/18 | 10/18 | *(+8)* | **Composite WITHHELD by the harness's own variance gate**: the `detects-stale-gate` without-arm scored [0, 3, 0] (sd 1.41) — not interpretable. The two stable cases: requires-clean-control +0.67 avg (with [2,2,2] vs without [1,2,1]); nottrigger clean in both arms (no signature leakage). |

**The honest pattern across all five:** the measured benefit concentrates in *distinctive
doctrine* the baseline does not have (never-reimplement, fresh-context forking, the
manuscript-is-not-the-oracle rule, the clean-control requirement). Cases that test knowledge
frontier baselines already carry (honest DiD, tolerance-first) measure ~0 — which is a fact
about those *cases*, not proof the skill is useless: procedural value (fork grids, ledgers,
budgets, gates) is invisible to one-shot Q&A grading. Writing better procedure-sensitive
cases is the recorded next step, not a reason to inflate these numbers.

## Workflow audit (2026-08-22, overnight)

A 14-component adversarial audit (85 agents: opus finders with mandatory verbatim quotes,
refute-biased verifiers that reproduced failing cases — one ran both gates under a PATH-shimmed
`date` to prove the expiry attribution wrong) returned **71 findings: 63 confirmed, 7
downgraded, 1 refuted**. All 63 confirmed findings were fixed in the same night, including 3
blockers (deploy.yml ordering that killed every real CI deploy; two false README claims) and
five bugs in gates that had themselves been "qualified" — proof that qualification covers the
seeded classes only, never the classes nobody seeded. 22 finder-stage minors were dropped
un-verified by the per-component cap (logged at drop time); they are preserved in the workflow
journal for later triage and are NOT counted as adjudicated.

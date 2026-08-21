# Qualification Ledger

Every check, gate, and review agent that is allowed to clear work must have a row here.
**A checker with no row is unqualified, and its green light means nothing.**

Written by `/vaccinate`. See [`verification-ladder.md`](../../.claude/references/verification-ladder.md) rung 0.

Verdicts: **PASS** (detects its named class at the stated threshold) · **FAIL** (misses it) ·
**BLOCKED** (could not be run — reason required; never record as PASS).

| Date | Target | Artifact | Defect classes | N | Recall | FPR | Baseline | Verdict |
|---|---|---|---|---|---|---|---|---|
| 2026-08-21 | `check-model-versions.sh` | `README.md` | T1 superseded-model-as-current | 1 | 1/1 | 0/0 on clean control | `grep -c "Opus 4.8"` also detects; gate's value is its allow-marker logic | **PASS** |
| 2026-08-21 | `check-skill-integrity.py` | `.claude/skills/capture-environment/SKILL.md` | T3 body invokes a tool absent from `allowed-tools` | 1 | 1/1 | 0/0 on clean control | none simpler (needs frontmatter↔body parse) | **PASS** |

| 2026-08-21 | `scripts/backtest.sh` (all 6 gates) | `README.md` | broken link · stale model · count drift · unfalsifiable superlative | 4 | **3/4** | 0/0 on clean control | n/a (composite) | **FAIL** → fixed, see next row |
| 2026-08-21 | `check-surface-sync.py` count patterns | `README.md` | template-verb count drift ("this template has N skills") | 3 | 3/3 | **0/3** on legitimate-prose controls ("start with 2-3 skills", "7 parallel agents", "clo-author ships 17 specialized agents") | bare `grep -c` would false-positive on all 3 controls | **PASS** |
| 2026-08-21 | `scripts/check-links.py` | `README.md`, `CLAUDE.md` | missing file · unresolvable heading anchor | 2 | 2/2 | 0/0 on clean control | none simpler (needs anchor slugging) | **PASS** |
| 2026-08-21 | `scripts/validate-findings.py` | synthetic findings array | wrapper-not-array · missing field · unknown field · bad enum · non-derived id · duplicate id · line 0 · malformed JSON | 8 | 8/8 | 0/1 (valid finding accepted) | none | **PASS** |

| 2026-08-21 | `scripts/backtest.sh` — **full stress test, all 7 gates** | `README.md`, `CLAUDE.md`, `docs/index.html`, `scripts/`, a skill | count drift (compound) · count drift (template verb) · superseded model · broken link · broken anchor · superlative · stale auto-mode claim · root scratch file · draft copy · undeclared tool | 10 | **10/10** | **0/1** on the clean-repo control | n/a (composite) | **PASS** |
| 2026-08-21 | `check-surface-sync.py` coverage of `docs/index.html` | landing page | count drift on the published page | 1 | 1/1 | 0/0 | n/a | **PASS** (see note) |

## Not yet qualified

These are relied upon and have **never been measured**. Until they have a row, treat their
output as unverified.

| Target | Why it matters |
|---|---|
| `/review-paper --peer` | used for submission decisions |
| `claim-verifier` (CoVe) | HIGH-WARN gate-refuses `/commit` |
| `/audit-reproducibility` | gates the replication package |
| `/seven-pass-review` | submission-readiness |
| `quality_score.py` | the 80/90/95 thresholds |
| `check-surface-sync.py` | pre-commit gate |
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

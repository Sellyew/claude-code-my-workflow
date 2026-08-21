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

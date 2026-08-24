---
paths:
  - "scripts/**/*.R"
  - "Figures/**/*.R"
---

# Replication-First Protocol

**Core principle:** Replicate original results to the dot BEFORE extending.

---

## Phase 1: Inventory & Baseline

Before writing any R code:

- [ ] Read the paper's replication README
- [ ] Inventory replication package: language, data files, scripts, outputs
- [ ] Record gold standard numbers from the paper:

```markdown
## Replication Targets: [Paper Author (Year)]

| Target | Table/Figure | Value | SE/CI | Notes |
|--------|-------------|-------|-------|-------|
| Main ATT | Table 2, Col 3 | -1.632 | (0.584) | Primary specification |
```

- [ ] Store targets in `quality_reports/LectureNN_replication_targets.md` or as RDS

---

## Phase 2: Translate & Execute

- [ ] Follow `r-code-conventions.md` for all R coding standards
- [ ] Translate line-by-line initially -- don't "improve" during replication
- [ ] Match original specification exactly (covariates, sample, clustering, SE computation)
- [ ] Save all intermediate results as RDS

### Stata to R Translation Pitfalls

<!-- Customize: Add pitfalls specific to your field -->

| Stata | R | Trap |
|-------|---|------|
| `reg y x, cluster(id)` | `feols(y ~ x, cluster = ~id)` | Stata clusters df-adjust differently from some R packages |
| `areg y x, absorb(id)` | `feols(y ~ x \| id)` | Check demeaning method matches |
| `probit` for PS | `glm(family=binomial(link="probit"))` | R default logit != Stata default in some commands |
| `bootstrap, reps(999)` | Depends on method | Match seed, reps, and bootstrap type exactly |

---

## Phase 3: Verify Match

Verification runs in two directions. **Vertically**, each claim is checked against the output
that produced it, under the tolerances below. **Horizontally**, each claim is checked against
every *other* artifact that displays the same number — see [The horizontal check](#the-horizontal-check).
A value can clear every vertical check and still be a month out of date on a slide.

### Tolerance Thresholds

| Type | Tolerance | Rationale |
|------|-----------|-----------|
| Integers (N, counts) | Exact match | No reason for any difference |
| Point estimates | < 0.01 | Rounding in paper display |
| Standard errors | < 0.05 | Bootstrap/clustering variation |
| P-values | Same significance level | Exact p may differ slightly |
| Percentages | < 0.1pp | Display rounding |

### If Mismatch

**Do NOT proceed to extensions.** Isolate which step introduces the difference, check common causes (sample size, SE computation, default options, variable definitions), and document the investigation even if unresolved. To localize *which* step drifted, hand off to [`/diagnose`](../skills/diagnose/SKILL.md) (reproduce → minimise → bisect the pipeline) — it is the single-claim root-cause counterpart to `/audit-reproducibility`'s whole-paper check.

**The mismatch does not presume the code is correct.** The on-disk output is a *challenger*, not an oracle — a refactor may have broken a previously-correct table, so the *manuscript* number may be the right one and the code the stale/buggy side. Frame it as "one of {paper, code} must change — isolate which," never "revert the code to match the paper."

**A defensible alternative is not a failure.** If the gap is explained by a *concrete, named alternative specification* (e.g. `reghdfe` vs `feols` clustering df, a different bandwidth-selection rule, MC seed/reps, display rounding), record that named alternative and mark the claim **EXPLAINED** rather than FAIL — see the `status` semantics below. A blank or vague note ("unclear") never downgrades a FAIL.

### Replication Report

Save to `quality_reports/LectureNN_replication_report.md`:

```markdown
# Replication Report: [Paper Author (Year)]
**Date:** [YYYY-MM-DD]
**Original language:** [Stata/R/etc.]
**R translation:** [script path]

## Summary
- **Targets checked / Passed / Failed:** N / M / K
- **Overall:** [REPLICATED / PARTIAL / FAILED]

## Results Comparison

| Target | Paper | Ours | Diff | Status |
|--------|-------|------|------|--------|

## Discrepancies (if any)
- **Target:** X | **Investigation:** ... | **Resolution:** ...

## Environment
- R version, key packages (with versions), data source
```

---

## Phase 4: Only Then Extend

After replication is verified (all targets PASS):

- [ ] Commit replication script: "Replicate [Paper] Table X -- all targets match"
- [ ] Now extend with course-specific modifications (different estimators, new figures, etc.)
- [ ] Each extension builds on the verified baseline

---

## Enforcement

This rule is enforced by the [`/audit-reproducibility`](../skills/audit-reproducibility/SKILL.md) skill. It parses numeric claims from a manuscript, locates matching values in `scripts/R/_outputs/` (or the user-specified outputs directory), and compares against the tolerance thresholds above. Run it:

- **Before submission** — `/audit-reproducibility path/to/manuscript.tex`
- **Before releasing a replication package** — same invocation; aim for zero FAILs.
- **As a pre-commit gate** — wire into `/commit` when the diff touches both manuscript and analysis files.

The skill exits 1 on any tolerance violation, so it integrates cleanly with quality gates.

---

## Claims Provenance: `passport.yaml`

A passport is a single per-paper, per-branch YAML file at `quality_reports/passports/<paper-slug>.yaml` that records, for each verified numeric claim in the manuscript, the script invocation and output file that produced it. The contract is intentionally narrow: numeric claims only (point estimates, standard errors, p-values, sample sizes, percentages from tables/figures), not prose claims (which `/verify-claims` handles separately).

`templates/passport-template.yaml` is the starter file. Forkers should copy it once per paper.

### Schema

```yaml
paper:
  slug: <paper-slug>                              # used in filename + report headings
  title: <full paper title>
  branch: <git branch on which this passport is current>
  last_audit: <ISO-8601 timestamp>
  last_audit_by: "/audit-reproducibility"         # or human, or another skill

claims:
  - id: C1                                        # stable identifier (used in cross-references)
    claim: "ATT = -1.632 (SE 0.584, N=4291)"     # exact text or paraphrase from manuscript
    location: "manuscript.tex:Table 2, Col 3"     # primary display (kept; source of truth for the paper)
    appears_in:                                   # EVERY artifact that displays this number
      - path: manuscript.tex                      #   file a reader sees it in
        locator: "Table 2, Col 3"                 #   where inside that file
        display_precision: 3                      #   decimals SHOWN here (0 = integer)
      - path: Slides/Lecture04_Results.tex
        locator: "frame 'Main result', highlight box"
        display_precision: 2                      #   coarser → this pair compares at 2
    source_file: scripts/R/03_analyze.R           # script that produced the value
    source_line: 147                              # nearest line in the script
    output_file: scripts/R/_outputs/main_model.rds # where the value lives on disk
    output_field: att_overall                      # field within the output (e.g., list element, column)
    tolerance:
      point_estimate: 0.01                         # absolute floor (atol); see typed rule below
      standard_error: 0.05
      rtol: 0.001                                  # optional relative component: pass if
                                                   #   |x - y| <= atol + rtol * |reported|
      units: "log points"                          # units + display rounding make the
      display_rounding: 3                          #   comparison meaningful across scales
      n: exact
    last_verified_on: <ISO-8601>
    last_verified_by: "/audit-reproducibility"
    status: PASS                                   # PASS | FAIL | EXPLAINED | STALE | UNVERIFIED
    notes: |
      Optional notes — e.g., "matches paper to 3 decimals; SE differs in 4th
      decimal due to clustering df adjustment, within tolerance."
      To downgrade a FAIL to EXPLAINED, this field MUST name a concrete
      alternative spec, e.g. "reghdfe vs feols clustering-df adjustment;
      under the reghdfe small-sample correction the published −1.19 matches
      the script."
```

### The horizontal check

The fields above verify a claim **vertically** — the number in the paper against the output that
produced it. That leaves untouched the failure a multi-artifact project produces most reliably:
the analysis is rerun, the manuscript table is regenerated from the new output, and the slide
deck, the supplement, or the poster quoting the same number is **not**. Every vertical check
still passes. Two artifacts on disk now disagree about one quantity, and the one an audience
sees is the stale one.

`appears_in` closes that gap by making the second and third display of a number *declared*
rather than remembered. Per claim:

1. **Locate every declared display.** Open each `appears_in[].path` and read the value at its
   `locator`.
2. **Compare pairwise at the coarser precision.** Two displays agree when they are equal after
   both are rounded to the **smaller** of their two `display_precision` values. A deck showing
   `0.34` where the paper shows `0.342` agrees; a deck showing `0.29` does not. The coarser side
   governs because a rounding difference is a display choice and a value difference is a defect
   — the rule separates them without anyone having to argue the case.
3. **A display that cannot be found is a FAIL, never a skip.** If a declared `path` is missing,
   or no value matches at its `locator`, the claim resolves to FAIL. A locator that has quietly
   stopped matching is precisely the state in which a stale number hides; resolving it to
   "skipped" would silence the check exactly when it should be loudest.

The `tolerance:` block governs the **vertical** comparison only — including its
`display_rounding`, which describes the *reported value's* own precision, where
`display_precision` describes one artifact's rendering of it. Two displays of one number are not
two measurements, they are two copies, so the horizontal comparison admits no tolerance beyond
the rounding in step 2, and no `notes` entry downgrades a horizontal disagreement to EXPLAINED. If the deck genuinely shows a *different* specification, it is a
different claim and gets its own passport entry.

A claim with no `appears_in` list is read as declaring its `location:` alone: vertical checks
run as before, and the audit reports it as horizontally unchecked rather than horizontally
clean. Passports written before this field existed keep working unchanged.

### `status` semantics

- **PASS** — last audit confirmed the claim within tolerance, and every declared display agrees at the coarser precision.
- **FAIL** — last audit detected a discrepancy outside tolerance **and** no concrete named alternative is recorded in `notes`; or two declared displays disagree; or an `appears_in` entry could not be located in its file. Blocks `/commit` for the affected files unless explicit override.
- **EXPLAINED** — outside tolerance, **but** `notes` records a *specific named alternative specification* that accounts for the gap (defensible alternative, paper-corrected, or code-corrected). Surfaced in the audit report and meant to flow into a response-to-referees; does **not** block. The hard floor holds: an UNMATCHED claim or a note without a named alternative stays FAIL — `/audit-reproducibility` never downgrades on a blank or vague note.
- **STALE** — the underlying `source_file` or `output_file`, **or any `appears_in` path**, was modified after `last_verified_on`. Re-run `/audit-reproducibility` to refresh. A touched display is as much a reason to re-check as a touched script: it is the edit that puts two artifacts out of step.
- **UNVERIFIED** — the claim was added to the manuscript but never run through `/audit-reproducibility`. Should not appear in a submission-ready passport.

### Integration

- **`/audit-reproducibility`** reads the passport at start, writes back after every claim audit. Failed claims are reported with their `id` and `location` so the author can find them in the manuscript instantly.
- **`/commit`** reads the passport when a diff touches both `manuscript.tex` (or .qmd) and any `source_file` listed. If the passport contains any FAIL or STALE for a claim whose `source_file` is in the diff, `/commit` halts (advisory by default; gate-refuse if `--strict-passport` is set in `.claude/settings.json`). **EXPLAINED claims do not halt** — the author has already recorded a defensible named alternative.
- **`.claude/hooks/claim-reconcile.py`** (PostToolUse) watches both links and nudges. Writing a tracked `source_file` / `output_file` names the claims whose number may have moved; writing a file declared in `appears_in` names the claims whose *other* displays were **not** edited and may now disagree (a claim with a single declared display has no sibling, so it stays quiet). The hook counts declarations by path — it never reads a value. It marks the moment two artifacts can fall out of step; the comparison itself, vertical and horizontal, runs in `/audit-reproducibility`.
- **`/review-paper`** (default mode + `--peer`) appends a summary section to its report when the passport exists: `claims: N total, PASS: A, FAIL: B, EXPLAINED: E, STALE: C, UNVERIFIED: D`. Editors and referees know whether numeric claims have been independently verified at draft time — and EXPLAINED rows tell them which contested numbers already carry a documented justification.

### Inspiration

The pattern is borrowed from [Imbad0202/academic-research-skills](https://github.com/Imbad0202/academic-research-skills)'s "Material Passport" concept (a YAML state-file threaded through their pipeline). Their schema is heavier (13 contracts, threaded through ~6 agents); ours is deliberately scoped to numeric-claim provenance only. Forkers who need broader provenance tracking can extend the schema or vendor ARS's design directly.

### Anti-patterns

- **Do not auto-populate** the passport at `/audit-reproducibility` time without showing the user the inferred mapping. Source-line inference is best-effort; the author confirms.
- **Do not promote UNVERIFIED claims to PASS** without running the actual numeric audit. The passport is a verified-state artifact; bypassing the verification defeats the purpose.
- **Do not reconcile a horizontal disagreement by hand-editing whichever display looks wrong.** Two displays that disagree tell you nothing about *which* is right. Re-derive both from the output the claim points at, then re-check. Typing the paper's value into the deck turns the check green while leaving open the possibility that the paper was the stale side.
- **Do not use the passport as a substitute for `/verify-claims`.** The passport handles numeric claims with code provenance; `/verify-claims` handles citation and named-entity claims with literature provenance. Both run.

## Auto memory is an un-logged context input

Claude Code's **native auto memory** is on by default and is machine-local
(`~/.claude/projects/<project>/memory/`). It can shape a session invisibly to anyone
replicating your work: a preference or correction recorded weeks ago is context a replicator
does not have and cannot see.

This is not a correctness bug — it is an **auditability** one, and the fix is disclosure, not
abstinence:

- For a session that produces a **reported number**, note in the analysis log that auto memory
  was active. One line.
- If a run must be *exactly* reconstructible from the repo alone — a final replication-package
  build, a numbers-freeze before submission — disable it for that run:
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`.
- Anything that genuinely belongs to the project, rather than to your machine, should be
  promoted into the committed `MEMORY.md` via [`/promote-memory`](../skills/promote-memory/SKILL.md)
  — where a replicator can actually read it.

The principle is the same one behind pinned commits and lockfiles: **if it influenced the
result, it should be visible to whoever checks the result.**

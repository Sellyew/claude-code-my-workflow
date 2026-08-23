# Screening Rubric: [What Is Being Screened]

**Date:** [YYYY-MM-DD]
**Screened by:** [N parallel agents / by hand]
**Default verdict:** EXCLUDE

> Write this **before** the screen runs. A rubric invented per candidate is not a rubric — it is
> the screener's taste, applied N times
> ([`research-agent-laws.md`](../.claude/references/research-agent-laws.md) law 21).

---

## The question this screen answers

[One sentence. What survives the screen, and what will be done with it. If the answer is "we'll
see", the screen is premature — the criteria below cannot be written without it.]

---

## Criteria

INCLUDE requires **every** criterion to hold, each with cited evidence. Anything else is EXCLUDE.

| # | Criterion (must hold) | How it is checked | Verdict if it fails |
|---|-----------------------|-------------------|---------------------|
| C1 | [requirement] | [the field, file, page, or command that decides it] | EXCLUDE |
| C2 | [requirement] | [how it is checked] | EXCLUDE |
| C3 | [disqualifier stated positively] | [how it is checked] | EXCLUDE |

**Exclusion is the default, not the failure case.** *"Might be relevant"*, *"looks promising"*,
and *"could not check"* are exclusions — the first two because they cite nothing, the third
because an unverified criterion has not held.

---

## Per-candidate evidence

Each candidate returns one row, and each verdict names **where** it came from:

| Field | Requirement |
|-------|-------------|
| `id` | Stable identifier assigned by the dispatcher **before** the screen runs |
| `verdict` | INCLUDE / EXCLUDE / BORDERLINE |
| `failing_criterion` | The first criterion that failed (empty for INCLUDE) |
| `evidence` | Locator plus quoted text — page, line, field name, or command output |

A verdict with no locator is not a result; it is re-screened. Verdicts join to candidates **by
`id`**, never by a title or a name the screener wrote down — a model-authored key silently drops
rows, and a dropped row looks exactly like an exclusion.

---

## Borderline protocol

A candidate that fails **only** on a criterion the screener could not verify is marked
**BORDERLINE** and returned unresolved, with the single question that would settle it. Borderlines
are decided by the dispatcher **after the whole wave returns** — never by the screening agent, and
never by whichever agent returned first.

**Rubric-failure threshold:** if borderlines exceed [X %] of candidates, the rubric is the
problem. Rewrite it and re-run the screen; do not adjudicate a hundred coin flips one at a time.

---

## Adjudication (after the whole wave returns)

Early returns are **status, not input.** Nothing is decided until every screener has reported;
the wave is then reconciled in one pass into a single table:

| id | Candidate | Verdict | Failing criterion | Evidence | Screener |
|----|-----------|---------|-------------------|----------|----------|
| [id] | [name] | EXCLUDE | C2 | [locator + quote] | [agent] |
| [id] | [name] | INCLUDE | — | [locator + quote per criterion] | [agent] |

Two screeners disagreeing on one candidate is a **rubric defect** until shown otherwise: fix the
criterion's wording, then re-screen the affected candidates.

---

## Dispatcher spot-check

Before acting on the wave, re-screen a sample **by hand** against this rubric:

- **Sample size:** [max(3, 10 % of candidates)], drawn across verdicts — at least one INCLUDE,
  one EXCLUDE, and one BORDERLINE.
- **Disagreement on any sampled candidate invalidates the wave.** Repair the rubric and re-run;
  do not patch the individual verdict and keep the rest.

An unchecked screen is an opinion poll with citations.

---

## Filled example (synthetic)

**Question.** Which publicly available datasets could support an independent re-analysis of a
published result, using only what we can obtain and redistribute this term?

**Criteria.**

| # | Criterion (must hold) | How it is checked | Verdict if it fails |
|---|-----------------------|-------------------|---------------------|
| C1 | Record-level observations, not published tabulations only | Codebook lists an observation unit and per-record variables | EXCLUDE |
| C2 | Covers the full period the re-analysis needs | Coverage statement or first/last observation date in the documentation | EXCLUDE |
| C3 | Licence permits redistribution of derived files | Licence text names redistribution or an open licence | EXCLUDE |
| C4 | Variable definitions documented well enough to reconstruct the outcome | Codebook defines the outcome and its denominator | EXCLUDE |
| C5 | Access obtainable without an agreement that outlasts the project | Access page states the process and typical turnaround | EXCLUDE |

**Sample rows.**

| id | Candidate | Verdict | Failing criterion | Evidence | Screener |
|----|-----------|---------|-------------------|----------|----------|
| `c-014` | National monitoring archive | INCLUDE | — | Codebook p. 4 "one record per site-day"; coverage 2009–2024; CC-BY; outcome defined p. 11; instant download | agent-2 |
| `c-021` | Regional summary series | EXCLUDE | C1 | Landing page: "annual totals by region"; no record-level file offered | agent-1 |
| `c-027` | Partner registry extract | EXCLUDE | C5 | Access page: data-use agreement, "8–12 weeks", exceeds the term | agent-3 |
| `c-033` | University repository copy | BORDERLINE | C3 | Deposit page shows no licence; question that would settle it: does the deposit record carry a licence field? | agent-2 |

**Spot-check.** Three candidates re-screened by hand (`c-014`, `c-021`, `c-033`); all three
verdicts reproduced from the cited locators.

---

## Cross-references

- [`research-agent-laws.md`](../.claude/references/research-agent-laws.md) — law 21 (screens and waves), law 1 (read the artifact, and the join that dropped rows)
- [`orchestrator-protocol.md`](../.claude/rules/orchestrator-protocol.md) — screening fan-outs as a runtime primitive
- [`executor-contract.md`](executor-contract.md) — the dispatch contract each screener is launched under

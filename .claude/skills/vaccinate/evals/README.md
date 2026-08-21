# Skill evals — the gap between *verified* and *measured*

The seven gates in `./scripts/backtest.sh` prove the repo is **internally consistent and
currently true**. They cannot prove that a skill's instructions actually produce good output.
That is a different claim and it needs a different instrument.

**Two things to measure, separately.** Seeing a skill trigger tells you Claude *found* it, not
that it *did what you intended*:

| Question | Instrument |
|---|---|
| Does Claude invoke this skill on the prompts it should — and not on the ones it shouldn't? | description-trigger evals |
| When it does run, is the output what you wanted? | output-quality evals |

## The method: a baseline comparison

Collect a few realistic prompts. Run each in a **fresh session** with the skill available, and
again with it disabled. Compare. A fresh session matters because leftover context from
authoring the skill masks gaps in the written instructions — you will believe the skill says
something it only implied.

If the with-skill run is not better, the skill is costing context for nothing.

## Running them

The `skill-creator` plugin automates the loop:

```
/plugin marketplace add anthropics/claude-plugins-official
/plugin install skill-creator@claude-plugins-official
```

Then ask it to evaluate a skill. It stores cases in `evals/evals.json`, spawns a **subagent per
case** so each starts clean, records tokens and duration, grades assertions into
`grading.json`, and aggregates with-skill vs without-skill into `benchmark.json` — so you can
weigh the pass-rate improvement against the token and time cost.

It also does the two things hardest to do by hand: a **blind A/B between two versions** of a
skill, so you can confirm an edit is an improvement before committing it, and
**description tuning** — generating should-trigger and should-not-trigger prompts, measuring
the hit rate, and proposing description edits when the skill fires on the wrong requests.

## Which skills to evaluate first

Rank by *cost of being wrong*, not by how often they run:

1. **`/review-paper --peer`** — informs submission decisions.
2. **`claim-verifier`** — HIGH-WARN gate-refuses `/commit`.
3. **`/audit-reproducibility`** — gates the replication package.
4. **`/challenge`** — its output becomes a robustness claim in a paper.
5. **`/did-event-study`** — drives estimators whose defaults change the estimand.

## The relationship to `/vaccinate`

They are complementary and neither substitutes for the other:

- **`/vaccinate`** asks *can this checker detect a defect I planted?* — a **recall** question
  about a checker.
- **Evals** ask *does this skill produce better work than not having it?* — a **quality**
  question about an instruction set.

A skill can pass evals and still be a useless reviewer: it produces well-formed, plausible
findings that miss real defects. Only `/vaccinate` catches that. And a checker can vaccinate
cleanly while its skill wrapper triggers on the wrong prompts. Run both.

## Recording results

Eval results go in the same ledger as qualification runs
(`quality_reports/qualification/LEDGER.md`), with the skill name, the case count, pass rate
with and without, and the token delta. **An eval with no recorded baseline is an anecdote.**

> **Not yet run for this template.** No skill here has been eval'd. That is stated plainly
> rather than left implicit — the qualification ledger lists which checks are unqualified by
> name, and this is the same honesty applied to skills.

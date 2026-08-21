# The Verification Ladder — how we check, and how we loop

**The premise:** producing the work is no longer the slow part. **Checking it is.** Every
rung below exists because a cheaper rung let something through.

> **The incident this file exists for.** Twenty bugs were deliberately planted in a working
> codebase, and the review agents were asked to check it again. **They reported everything
> was fine.** Recall: 0/20. The fix was not a better prompt — it was to start *measuring the
> checkers*. Think of it as a vaccine: a small, controlled dose of error that strengthens the
> whole system.
>
> **Consequence, and it is the load-bearing rule here: an unqualified check is not weak
> evidence. It is none.**

---

## Rung 0 — Qualify the checker (before trusting any green)

Before a test, gate, comparator, or AI reviewer is allowed to clear anything:

1. **Name the failure** it targets.
2. **Seed that failure** and confirm it goes **red**.
3. **Run a clean control** and count false alarms — a finding on clean work counts only if it
   is *factually false*, not merely unwelcome.
4. **Compare against a simpler baseline.** More agents is not presumed better than grep.
5. **Confirm it actually ran** on the current object.

Record a ledger row: date · artifact · seeded classes · **recall** · **false-positive rate** ·
verdict `PASS / FAIL / BLOCKED`.

**A bad seed reads exactly like a broken gate.** If you seed a defect into an artifact that
already permits the thing you seeded, "all checks pass" is *correct* and you have learned
nothing. Verify the seed creates a real violation first.

---

## Rung 1 — Deterministic gates (no model in the loop)

Classes that are decidable belong in a script, never in an agent prompt. Agents miss them
because the prompt lists them among many checks and attention drifts. **The script never
drifts.**

- `check-surface-sync.py` — counts and enumerative tables match disk
- `check-skill-integrity.py` — frontmatter ↔ body tool parity, anchors, flag parity
- `check-model-versions.sh` — model currency, **with an external oracle and an expiry**
- `.githooks/pre-commit` — runs the above on every commit (live only after `install-hooks.sh`)

**A gate that proves internal consistency is not a currency gate.** Surfaces agreeing *with
each other* is compatible with all of them being wrong. Any currency claim needs an external
source **and** a `verified_on` expiry that fails the gate when stale.

---

## Rung 2 — Artifact verification: four layers, in order

| Layer | Question | Typical miss |
|---|---|---|
| **Existence** | is the artifact there? | — |
| **Substantiveness** | is it *real*, or a stub? | placeholder values, hardcoded constants, TODO markers, functions that return the input |
| **Wiring** | is it actually connected? | a figure regenerated but never `\input`, a script whose output nothing reads |
| **Coherence** | do the pieces tell one story that answers the question? | every part passes, the whole is still wrong |

Only the fourth catches "all the checks passed and the paper is still wrong."

---

## Rung 3 — Independence (the fresh-context fork)

A reviewer that has seen the draft cannot un-see it. Three ways to enforce independence, and
they are **not** interchangeable:

| Mechanism | Independence via | Best for |
|---|---|---|
| **Critic + fixer** | role tension (critic cannot fix; fixer cannot approve) | presentation and structural defects |
| **Cross-artifact traversal** | the dependency graph (paper → table → output → script) | paper ↔ code consistency |
| **CoVe fresh-context fork** | context isolation — the verifier never sees the draft | fabricated citations, wrong numbers, misattribution |

Two practices that cost nothing and change outcomes:

- **Independent assessment before reading the plan.** Have the verifier decide what *should*
  exist before it learns what was promised. Otherwise it grades conformance, not adequacy.
- **Blind the judge.** Strip revision markers before a comparison, or it grades the diff.

---

## Rung 4 — Analytic verification (does the *claim* survive?)

Rungs 1–3 check **artifacts**. This rung checks the **claim** — whether the result survives
choices a competent, honest analyst could have made differently.

Why it is separate: in a controlled study, **150 autonomous agents** given the same data and
question produced effect-size interquartile ranges up to **~10.7 %/yr**, and the divergence
concentrated in **discrete measure-choice forks** (dollar vs share volume; trade-level vs
Amihud), not estimation noise. Two results matter here:

- **AI peer review left that spread essentially unchanged.** Review catches errors; it does
  not reduce analytical-choice variance. Do not claim otherwise.
- Exposure to exemplar papers collapsed the spread by 80–99 % — **convergence by imitation,
  not by correctness.** Herding is not agreement.

So: enumerate the forks and report the distribution.

- **Specification curve / multiverse** over measure definition, sample filter, control set,
  clustering level, weighting, winsorization.
- **Named computable sensitivity statistics** — turn "challenge the assumption" into a number:
  Rambachan–Roth honest DiD (**never** naive pre-testing), Oster δ, E-value,
  Cinelli–Hazlett robustness value, Rosenbaum Γ, McCrary/Cattaneo density.
- **Placebo and falsification** — negative outcomes, negative exposures, timing placebos.
- Label each statistic **executable here** vs **describe-and-cite** — honesty about what your
  environment can actually run is itself a verification step.

---

## Rung 5 — The ledger (make adaptive search inspectable)

Agentic tooling makes specification search fast and cheap, which widens hidden researcher
degrees of freedom. The answer is not to forbid search — it is to **record** it.

Four artifacts:

1. **An instruction contract** — objective, admissible modifications, and a **search budget**.
2. **An immutable evaluator** — the scoring harness, never edited during the search.
3. **A single editable surface** — the one file the agent may change.
4. **An append-only ledger** — every attempt: identifier, score, outcome
   (`keep / discard / crash`), and a one-line description of the strategy.

Then: **pre-commit the interpretation before running the test** — write what result would
SUPPORT versus WEAKEN the claim *first*. The ledger is the arbiter. This closes the
garden-of-forking-paths gap that hypothesis-only preregistration leaves open.

**Record every attempt, including nulls and failures.** A ledger showing only supporting
tests is a fishing expedition with good PR.

**Reserve a holdout and evaluate it only after the search.** In-sample improvement does not
generalize: published runs of this protocol show relative RMSE going 0.510 → 0.811 and
0.808 → **1.089** out of sample.

Two elements worth carrying over from practice:

- **A fixed budget** makes runs comparable by construction.
- **A simplicity criterion.** A gain that adds twenty lines of hacky code is probably not
  worth it; an *equal* result from deleting code is a win. A robustness result that survives
  with **fewer** controls is a stronger result — the ledger should say so.

---

## Rung 6 — The external oracle (advisory, last)

See [`external-oracle-process.md`](external-oracle-process.md). It is last for a reason:
run exhaustive in-house coverage first so the oracle is **confirmation, not discovery**.

---

## How we loop

```
implement → verify (rung 1–2) → review (rung 3) → adjudicate → fix → re-verify
```

**Adjudicate, never ingest.** Every finding from anyone you did not write yourself — an AI
reviewer, a referee, a linter, a second model — is a **CANDIDATE** until checked against the
source. Verdicts: **CONFIRMED / REFUTED / DOWNGRADED**. Check the proposed *fix* too: a
reviewer can be right that something reads badly and wrong about why, and its patch can
introduce a real defect.

**Batch, do not drip.** Apply all confirmed fixes in one pass, re-verify, then run **at most
one** confirmation round. One-finding-per-round converges linearly and burns rounds.

**Stopping rule.** Stop when a round adds **no new CONFIRMED** defect — only held items and
exposition taste. Guards: a fallback round cap; a *two-strikes* rule (the same finding
surviving two rounds escalates to the human rather than being patched a third time); and a
spend ceiling.

**Carry a HELD list** of standing decisions so settled questions are not re-litigated every
round.

**Expect false positives by construction.** A reviewer prompted to find gaps will report some
even when the work is sound. Chasing every finding produces over-engineering. Tell reviewers
to flag only what affects correctness or the stated requirements — and treat "no new
confirmed defect" as a valid, useful answer.

---

## What is *not* automatic

No daemon. No post-plan-approval trigger. Every loop is started by a human or by a skill a
human invoked. An unattended multi-agent fix loop pointed at a submission, shared data, or a
co-author's draft is the failure mode this template refuses. **Documented non-goal, not a
missing feature.**

---

## Cross-references

- [`external-oracle-process.md`](external-oracle-process.md) · [`provenance-and-ground-truth.md`](provenance-and-ground-truth.md)
- [`orchestration-schemas.md`](orchestration-schemas.md) — FINDING / SCORECARD / RUN_CONFIG
- [`.claude/rules/orchestrator-protocol.md`](../rules/orchestrator-protocol.md) · [`.claude/rules/verification-protocol.md`](../rules/verification-protocol.md)

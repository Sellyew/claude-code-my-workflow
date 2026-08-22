# Named sensitivity statistics — turning "challenge the assumption" into a number

An identifying assumption cannot be tested. It can be **bounded**. Each statistic below answers
a specific question, has a defensible reference implementation, and should be reported with the
benchmark that makes it interpretable — a robustness value with no comparison is decoration.

**Never reimplement these.** Drive the canonical package. A hand-rolled sensitivity statistic
is an unqualified check.

---

## Unobserved confounding

### E-value
**Question:** how strong would an unmeasured confounder's associations with both treatment and
outcome have to be, on the risk-ratio scale, to explain away the estimate?
**Report:** the E-value for the point estimate **and** for the CI limit nearest the null. The
second is the one that matters — an E-value of 2.1 with a CI-limit E-value of 1.02 is fragile.
**Implementation:** closed form; `EValue` (R).
**Watch:** defined on the risk-ratio scale. Converting a linear-model coefficient requires an
approximation — state which one.

### Cinelli–Hazlett robustness value (RV)
**Question:** what share of residual variance in both treatment and outcome would a confounder
need to explain to bring the estimate to zero (or past a threshold)?
**Report:** `RV_{q=1}`, and the **benchmark** — the RV expressed as a multiple of an observed
covariate's strength ("a confounder 3.2× as strong as region fixed effects").
**Implementation:** `sensemakr` (R), closed form from a t-value and residual df.
**Watch:** RV is about *linear* confounding in the estimated model. It says nothing about
functional-form error.

### Oster δ
**Question:** how large must selection on unobservables be, relative to selection on
observables, to drive the coefficient to zero?
**Report:** δ **with the assumed `R²max`** — δ is meaningless without it. State the rule used —
commonly `R²max = min(1.3 × R̃², 1)`, with Oster's cap, since an R²max above 1 is impossible —
and show sensitivity to it.
**Implementation:** `psacalc` (Stata), `robomit` (R).
**Watch:** assumes proportional selection. Widely reported, frequently reported without its
`R²max`, which makes it uninterpretable.

---

## Matched and stratified designs

### Rosenbaum Γ bounds
**Question:** how much would treatment odds have to differ within a matched pair or set, due
to an unobserved covariate, before the inference changes?
**Report:** the Γ at which the p-value crosses the threshold, and the design sensitivity.
**Implementation:** `sensitivitymv`, `rbounds` (R).
**Watch:** for matched designs — pairs, sets, or full matching. Do not apply to an unmatched
regression and call it a bound.

---

## Difference-in-differences

### Rambachan–Roth honest DiD
**Question:** if parallel trends holds only *approximately*, how large a violation can the
conclusion tolerate?
**Report:** breakdown `M̄` under relative-magnitudes restrictions, and the sensitivity plot.
Lead with relative magnitudes; smoothness restrictions are a secondary lens.
**Implementation:** `HonestDiD` (R), `honestdid` (Stata).
**Watch — this is the important one:** a **naive pre-test is not a substitute**. Failing to
reject a pre-trend is not evidence of parallel trends; it is frequently evidence of low power,
and pre-testing distorts the subsequent inference. Report honest DiD *instead of*, not
alongside, "pre-trends look flat."

### Comparison-group and base-period choices
Never-treated vs not-yet-treated, and universal vs varying base period, are **estimand
choices**, not robustness dials. Report them as forks in the specification curve and state
which the headline uses and why.

---

## Regression discontinuity

- **McCrary / Cattaneo density test** — manipulation of the running variable. `rddensity`.
- **Covariate placebo** — predetermined covariates must not jump at the cutoff.
- **Bandwidth sensitivity** — report the curve over bandwidths, not one MSE-optimal choice.
- **Donut** — drop observations immediately at the cutoff to probe heaping and sorting.
  Report the estimate and SE across donut radii, not just significance: a result that dies may
  reflect manipulation, heaping, **or simply the precision loss** from discarding the most
  informative observations. The donut localizes a concern; it does not adjudicate it.

---

## Instrumental variables

- **The exclusion restriction is not testable.** Any claim that a test "validates" it is wrong.
- **Over-identification** (Hansen J) is a joint test of *all* instruments' validity plus
  correct specification; rejecting tells you something is wrong, not what.
- **Placebo outcomes** the instrument should not affect are the most persuasive available
  evidence.
- **First-stage strength** — report the F, and use weak-instrument-robust inference
  (Anderson–Rubin) rather than only citing a rule of thumb.

---

## Reporting contract

For each statistic report: **the value**, **the benchmark that makes it interpretable**,
**the implementation and version**, and whether it was `executable-here` or
`describe-and-cite`.

A sensitivity analysis that reports only favourable statistics is not a sensitivity analysis.
If a bound is uncomfortably tight, that is the finding — the strongest sentence in a robustness
section is usually the one that retires the author's own preferred interpretation.

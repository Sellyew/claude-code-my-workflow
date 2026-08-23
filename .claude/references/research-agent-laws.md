# Laws for running agents on research infrastructure

Distilled from heavy agent use across an econometrics paper driven to submission, an
estimation package with a fail-closed audit surface, multi-day simulation campaigns, and
cross-language ports. **Every law was paid for by a real incident.** Nothing here is
aspirational; it is what failed, what caught the failure, and the habit that prevents a repeat.

Where a law is already mechanised elsewhere in this template, the cross-reference says so
rather than restating it — a rule stated twice becomes two rules that drift.

---

## Evidence

**1. A claim is not evidence. Read the artifact.**
An agent saying *"33 values compared, 0 drift"* is a claim; the CSV is the evidence. Before any
number reaches a decision or a reader, read it from a committed artifact. Verify by
**re-deriving**, not by re-asking.
*Incidents:* a determinism check reported as covering "the full SE set" when byte inspection of
its own artifact showed one name; a review reporting "62 confirmed" when its verifiers had
refuted 81 of 93 — a join had silently dropped them. And the inverse: a spot-check "refuting"
an agent's table turned out to be the checker's own error, because rows were matched on a
partial key. **When your check disagrees with the agent, suspect your check first.**

**2. Attribute before repairing; prove nulls with positive controls.**
When a gate fails or a number moves, establish *whose* change caused it — run the identical
check on the unchanged baseline. And *"nothing moved"* is evidence only if the detector
demonstrably fires on a known-affected case.
→ [`verification-ladder.md`](verification-ladder.md) rung 0; [`/vaccinate`](../skills/vaccinate/SKILL.md).

**3. Never re-bless a baseline in the commit that moves it.**
Land the change with the old pins so the gate *reports* the drift; re-bless in a follow-up
commit that cites the measurement.
→ [`provenance-and-ground-truth.md`](provenance-and-ground-truth.md) §6.

---

## Scope of a green result

**4. A green gate is scoped. Capability loss is invisible to output-equality tests.**
An equivalence suite that freezes outputs cannot see an output that silently *stopped being
produced*. Keep one standing harness that fingerprints the entire user-visible surface — every
number **and its presence** — and fail on **set changes**, not only value drift.
*Incident:* a 70,464-leaf byte-identical suite passed while half a diagnostic toolkit's outputs
had disappeared; the standing fingerprint caught it immediately (13,821 vs 29,748 numbers).
*Practice:* discover the surface live (from `formals()`, exports, or a manifest), sanity-check
every cell (NaN/Inf fails even without an error), refuse to run against the wrong source tree,
and refuse to bless numbers with no baseline.

**5. A gate that cannot fail is worse than no gate**, and **a check that could not run is not a
passing check.**
→ [`verification-ladder.md`](verification-ladder.md) rung 0.

**6. Dispatch on the realized experiment — never on labels, requests, or seals.**
Branch on what the computation actually did, not on what was asked for, what a field is named,
or whether an authentication wrapper is present. **Availability of a capability must never be
decided by an audit artifact.**
*Incident:* a diagnostic menu refused valid unsealed fits because a receipt validator required
seal digests — audit tooling had leaked into the production dispatch path.
*Corollary:* keep the audit layer **off** the hot path (opt-in), and keep the cheap always-on
operational record separate from the expensive opt-in attestation.

---

## Delegation

**7. Give executors the goal and the acceptance bar — never the implementation.**
A prescribed mechanism is a hypothesis wearing the clothes of an instruction. State the goal,
the bar, and what evidence settles it; offer mechanisms only as labelled hypotheses an executor
may refuse.
*Incidents, both directions:* an executor correctly refused a prescribed reconstruction after
measuring that the shipped code already met the bar; and a "faithful summary" written without a
ground-truth check was found by a hostile judge — holding the verbatim source — to contain four
unfaithful statements. **Executors need room to refuse; reviewers need the ground truth in hand.**

**8. The economy: expensive models plan and judge; cheap executors run gates.**
Decomposition, adjudication, delicate prose, and irreversible calls stay with the strongest
model. Execution goes to executors whose quality is enforced by **gates, not trust**. Long
computation goes to background processes costing zero tokens. Do not stack many parallel
fleets — rate limits produce partial failures. Give every agent: the gates its work must pass,
exact paths, an output contract, and the duty to cite an artifact for every number.
*Corollary:* when an agent stops without delivering its contract, **resume it and demand the
report** — do not re-run the work.
→ [`.claude/rules/model-routing.md`](../rules/model-routing.md).

**9. Protocolize the critic/fixer loop, or it runs forever.**
Bounded rounds with named signals and owners: **HOLD** (fixer retries, max N), **BLOCK**
(escalate to the orchestrator), **STOP** (human). The **two-strikes** rule escalates: the same finding id surviving rounds N and N+2 goes to the human, not to a third patch ([`orchestrator-protocol.md`](../rules/orchestrator-protocol.md)). Critics are
read-only **by mechanism**, not by instruction. Creators never self-score. Verdicts cite
invariant numbers, so a violation is a deduction rather than a taste.
→ [`.claude/rules/orchestrator-protocol.md`](../rules/orchestrator-protocol.md).

---

## Long-running work

**10. Long autonomy = runbooks on disk + notification-driven execution.**
Before any multi-hour stretch, write the **exact endgame runbook** — resume commands, file
paths, verdicts to check — to a version-controlled plan file **first**. Context gets
compressed; disk does not. Drive everything by completion notifications, never by polling.
**Monitors must cover every terminal state:** a filter matching only the success line is silent
through a crash, and silence looks identical to "still running." Compute ETAs from artifact
timestamps, not impressions.
*Incident:* a 33-hour eight-shard campaign executed its endgame entirely from the written
runbook across several context compressions.
*Practice:* **the pushed repo is the status report** — commit and push each stage as it lands,
including failures, plainly labelled.

**11. Standing routines: push on failure, silence on success.**
A nightly job that reports "all good" every day trains you to ignore it. Scheduled checks
report only when something needs a human.
→ [`scheduled-routines.md`](scheduled-routines.md).

**12. Parallelism must be provably run-shape-independent.**
Seed by **task**, not by worker: pre-generate one RNG stream per replication (L'Ecuyer) so
results are bit-identical at any core count — and **prove it** with a two-core vs four-core
bit-identity check before trusting any campaign. Worker-based seeding silently binds results to
the execution shape.
→ [`.claude/rules/simulation-conventions.md`](../rules/simulation-conventions.md).

---

## External models

**13. External-model consults are instruments. Operate them like instruments.**
Find the payload cliff empirically and split reviews into focused, single-decision runs — the
answers are sharper anyway. **Verify the transport, not the log**: the only send-committed
signal is the artifact. **Blind the judge** — strip revision markers before a fresh-context
comparison, or it grades the diff rather than the document. Ask reviewers for their **minimal
acceptable** version separately from their ideal; the delta is the decision currency.
**Advisory always** — verify every quoted passage against the source before relaying, and a
finding that dissolves under a file the reviewer never saw is **struck, not reported**.
→ [`external-oracle-process.md`](external-oracle-process.md).

---

## The record

**14. Defects become issues; corrections lead; supersession is explicit.**
When a previously relayed claim turns out wrong, **the correction is the first thing said**,
not a footnote. Generated artifacts produced together are regenerated together — never
merge-resolved file by file. When results are re-run at higher fidelity, the new artifact
**supersedes** the old explicitly, and predecessors are preserved unchanged as the record.
→ [`.claude/rules/issue-ledger.md`](../rules/issue-ledger.md), [`.claude/rules/progress-reports.md`](../rules/progress-reports.md).

**15. Memory needs a capture gate and a promotion policy.**
Five questions before anything is remembered: **durable? non-obvious? stable? specific? not
already captured?** Just-in-case memories are banned — they pollute the index and make the
useful ones unfindable. Promotion from local observation to committed knowledge is a
**reviewed act**, not an autosave.
→ [`.claude/skills/promote-memory/SKILL.md`](../skills/promote-memory/SKILL.md).

**16. Rules live with the code they govern; shared rules declare their upstream.**
A package that every audit gate governs had **zero guardrails of its own** — all its rules
lived in the consumer repo, invisible to anyone opening a session on the package directly. Put
a minimal `.claude/` in the governed repo. And every rule shared across repos carries a
**canonical-upstream marker**: one survey found five copies of a single rule spanning 61–194
lines with no way to tell which was current, and one rule making **opposite factual claims** in
two repos.

**17. One source of truth per repo; governance never ships.**
Exactly one place states each fact. Governance scaffolding stays out of the released artifact.
→ [`.claude/references/model-versions.md`](model-versions.md) is this template's worked example.

---

## The reporting stance that makes all of it credible

Prespecify the menu, then **print the cells that go against you with the same prominence as the
wins**. The strongest sentence in a results note is usually the one that retires your own
favourite consolation.

---

## Cross-references

- [`verification-ladder.md`](verification-ladder.md) · [`provenance-and-ground-truth.md`](provenance-and-ground-truth.md) · [`external-oracle-process.md`](external-oracle-process.md)
- [`.claude/rules/repo-hygiene.md`](../rules/repo-hygiene.md) — scratch must not become main

# External oracle consult — v2.6.0 guard design and doctrine

**Date:** 2026-08-23
**Oracle:** GPT-5.6 Sol Pro (ChatGPT Pro, browser transport), Pro effort
**Repository state reviewed:** branch `feat/v2.6-insight-incorporation`
**Artifacts:** [`prompt.md`](prompt.md) — the question as asked · [`transcript.md`](transcript.md) — the answer as returned, unedited

## Why this file exists

`.claude/references/external-oracle-process.md` requires that any claim resting on a consult
cite the archived transcript rather than "the oracle said" recalled from a session that has
ended. Five claims in this release rest on this consult — the cross-hook finding recorded in
`quality_reports/qualification/LEDGER.md`, the falsified drafts of laws 18, 19 and 21 in
`.claude/references/research-agent-laws.md`, and the correction recorded in `CHANGELOG.md`.
Before this file existed, none of them could be reopened by a later reader. An audit of this
branch caught that: the release mandated the archive and did not use it.

## Verdict returned

**HOLD the merge**, with four required changes. Its lead finding was not reachable by the
thirteen in-house review rounds that preceded it: the clean-tree guard read the tree at
`PreToolUse`, before the shell command ran, so a command that dirtied the tree and *then* ran a
history operation was allowed. Every internal round had tested chains in one direction only.

## Transport and reliability, recorded because it nearly produced a false report

The consult took **three attempts**. The first two exited **0** having sent nothing — the CLI
reports success on a failed send. Only inspecting the artifact revealed the failure; the exit
code was a lie. Had it been trusted, this release would have claimed an external review that
never happened.

The cause was the **payload cliff** that `external-oracle-process.md` itself names: 94 KB of hook
implementation was attached to answer questions about design. A 27 KB brief of docstrings and
laws went through. Two earlier diagnoses — a rejected `--browser-thinking-time` value, then
hidden-window mode — were both **wrong**, and are recorded here because a wrong diagnosis that
looks plausible is worth more to the next reader than a tidy one.

The third attempt then timed out at the CLI's capture stage after the model had been thinking
for 28 minutes; the answer existed and was recovered with `oracle session <name> --harvest`.
**A capture timeout is not an absent answer** — reattach before concluding the consult failed.

## Adjudication

Every finding was reproduced against real git in a scratch repository before being accepted;
none was taken on the referee's authority. What was adopted, what was deferred, and what was
withdrawn as a result is recorded in the `v2.6.0` entry of `CHANGELOG.md`. Two of its
recommendations were deliberately **not** taken: the trusted-wrapper design (its own cheaper
fallback was adopted instead), and closing the cross-hook seam for history operations (recorded
in the ledger rather than half-built).

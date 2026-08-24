# External oracle consult — v2.5.1 guard design and doctrine

**Date:** 2026-08-23
**Oracle:** GPT-5.6 Sol Pro (ChatGPT Pro, browser transport), Pro effort
**Repository state reviewed:** commit `6b8fa14` on `feat/v2.5.1-insight-incorporation` (a pinned
SHA, not the branch ref; the branch has advanced since, partly *because* of this consult)
**Conversation:** `https://chatgpt.com/c/6a8b746e-d9ac-83ea-bcd7-9ad89631c0e7`
**Sent:** the prompt below plus exactly one attachment, `oracle-brief.md` (27 KB) — both hook
module docstrings and the four new laws. **Not** the hook implementations: an earlier attempt
attached 94 KB of source and never sent (see *Transport* below).
**Artifacts:** [`prompt.md`](prompt.md) — the question as asked · [`transcript.md`](transcript.md) — the answer as returned, unedited · [`meta.json`](meta.json) — the same facts machine-readable

> **A count in this file was wrong, and it is the count the release's argument rests on.**
> An earlier draft said the referee's lead finding was unreachable by "thirteen" in-house rounds;
> `prompt.md` said "eleven". Derived by command (`ls bank/audit-r*-truth.json`), **ten** rounds had
> completed when the consult was sent, with an eleventh in flight. The prompt's figure counted the
> one still running; this file's was simply wrong. The prompt is left as it was asked — it is the
> record — and the corrected number is stated here.

## Why this file exists

`.claude/references/external-oracle-process.md` requires that any claim resting on a consult
cite the archived transcript rather than "the oracle said" recalled from a session that has
ended. Five claims in this release rest on this consult — the cross-hook finding recorded in
`quality_reports/qualification/LEDGER.md`, the falsified drafts of laws 18, 19 and 21 in
`.claude/references/research-agent-laws.md`, and the correction recorded in `CHANGELOG.md`.
Before this file existed, none of them could be reopened by a later reader. An audit of this
branch caught that: the release mandated the archive and did not use it.

## Verdict returned

**HOLD the merge**, with four required changes. Its lead finding was not reachable by the ten
in-house review rounds that preceded it: the clean-tree guard read the tree at `PreToolUse`,
before the shell command ran, so a command that dirtied the tree and *then* ran a history
operation was allowed. Every internal round had tested chains in one direction only.

**Bound the coverage before citing it.** `transcript.md` self-limits at the outset: *"The
supplied record contains the hooks' module docstrings, not their executable source. I therefore
adjudicate the stated design and guarantees."* So this consult is evidence about the **design and
what it claims**, and is not evidence that the implementation matches either. Everything it found
was reproduced against real git in a scratch repository before being accepted — none of it was
taken on the referee's authority.

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
withdrawn as a result is recorded in the `v2.5.1` entry of `CHANGELOG.md`. Two of its
recommendations were deliberately **not** taken: the trusted-wrapper design (its own cheaper
fallback was adopted instead), and closing the cross-hook seam for history operations (recorded
in the ledger rather than half-built).

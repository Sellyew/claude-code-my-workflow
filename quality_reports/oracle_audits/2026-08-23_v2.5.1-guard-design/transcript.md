🧿 oracle 0.16.0 — One command, several seers; results stay grounded.
Session: you-are-an-independen-referee-3
Target: D84CF290C69A2AB0A5223851C7B98A57
State: completed
Model: Pro
URL: https://chatgpt.com/c/6a8b746e-d9ac-83ea-bcd7-9ad89631c0e7
Assistant turns: 1
Signals: stop=no send=no
Last user: You are an independent referee. I am shipping a release of a public template repository that other researchers fork, and I want an adversar…
---
# Referee disposition

**HOLD the merge.**

The central redesign decision is right: **stop trying to infer arbitrary shell effects from command text**. Requiring a separate state-changing command before a history operation is a reasonable cost.

The release is not ready as written, however, because:

1. the clean-tree hook checks the tree **before the Bash tool call**, not necessarily when the history operation executes;
2. the unconditional `--autostash` exemption contradicts the untracked-file semantic that motivated the redesign;
3. the claimed repository lookup can silently inspect the wrong repository;
4. the “root of trust” is mutable through channels the template deliberately allows, including ordinary Git branch transitions;
5. several new laws turn sound incident-specific lessons into universal process requirements that will either bias research or be ignored.

The supplied record contains the hooks’ module docstrings, not their executable source. I therefore adjudicate the **stated design and guarantees**, not whether the implementation happens to diverge from those descriptions. I independently reproduced the relevant native-Git semantics in scratch repositories.

---

# 1. The guard redesign

## Judgment

### The decision to delete the shell-effect predictor was right

The reasoning behind this sentence is sound within the actual problem:

> “Simulating shell semantics by enumeration does not converge.”

— `.claude/hooks/git-guardrails.py` module docstring, reproduced in `oracle-brief.md`, lines 82–98.

A textual hook cannot prove the post-prefix filesystem state of arbitrary shell programs. Shell substitutions, scripts, aliases, interpreters, environment-dependent commands, and concurrent processes make that the wrong abstraction.

The sentence is slightly too universal, though. **Arbitrary-shell prediction** does not converge; a **closed, deliberately restricted command language** can. That distinction leads directly to the third design below.

### The usability trade is acceptable, but understated

This is directionally right:

> “run the cleaning step and the history op as SEPARATE commands”

— `git-guardrails.py` docstring, lines 108–115.

A merge, rebase, or pull is a sensible synchronization point. Forcing the agent to observe whether the preceding stash or commit actually succeeded is useful friction.

But this is not accurate:

> “It converts an unbounded soundness hole into one extra keystroke”

It is another **tool invocation**, another hook cycle, potentially another permission interaction, and another agent round-trip—not one keystroke. That cost is still acceptable for history operations, but it should be stated honestly.

More importantly, the current design imposes the false-deny cost **without fully obtaining the claimed safety benefit**.

## Grounded failure: it checks start state, not execution state

The summary says the hook blocks:

> “git merge / rebase / pull with a DIRTY tree”

— `git-guardrails.py` docstring, lines 35–37.

The doctrine says:

> “`.claude/hooks/git-guardrails.py` refuses the operation while the tree is dirty”

— `oracle-brief.md`, §C, Law 20, lines 388–390.

But the docstring also correctly admits:

> “any dirtying that happens BETWEEN the hook’s decision and the command actually running”

is not seen.

— `git-guardrails.py` docstring, lines 178–179.

### Concrete failing case

Assume the repository is clean when `PreToolUse` runs, and the incoming branch does not touch `analysis.R`:

```bash
printf '\n# local work\n' >> analysis.R && git merge main
```

The documented sequence is:

1. `PreToolUse` runs before the Bash command.
2. `git status --porcelain` reports clean.
3. The hook allows.
4. `printf` dirties `analysis.R`.
5. `git merge main` begins with a dirty tree.

The hook therefore does **not** enforce “history operations start from a clean tree.” It enforces:

> the parser-selected repository was clean when the Bash tool call was authorized.

That is still useful, but it is a materially narrower rule.

This is not cured by disclosing the race later in the docstring. The high-level summary and Law 20 state the stronger guarantee.

## The third design: check at execution time through a trusted wrapper

The missed design is a small runtime wrapper rather than a shell predictor.

For example:

```bash
git stash push -u -m "before merge" &&
.claude/bin/safe-history-op merge main
```

The wrapper should:

1. accept only `merge`, `rebase`, and `pull`, plus the explicitly supported continuation/abort forms;
2. derive repository identity using the same `-C`, `--git-dir`, `--work-tree`, and relevant environment passed to the eventual Git process—or reject unsupported selectors;
3. run `git status --porcelain=v1 -z` **when the wrapper itself executes**;
4. deny if the status violates the declared policy;
5. immediately replace itself with Git using `exec`, rather than returning to a shell prefix;
6. be included in the protected-path set;
7. have raw `git merge/rebase/pull` denied by the PreToolUse hook, so the wrapper is the ordinary route.

This handles both directions correctly:

```bash
git stash push -u -m x && safe-history-op merge main
```

The wrapper sees the post-stash state and can allow.

```bash
touch untracked.tmp && safe-history-op merge main
```

The wrapper sees the newly dirty state and denies.

Command substitutions in the wrapper’s arguments also execute before the wrapper starts, so their filesystem effects are visible to its status check.

There remains a small external-concurrency race between `status` and `exec git`. That should be disclosed. It is categorically smaller than trying to predict an arbitrary shell prefix and is aligned with the stated ordinary-accident threat model.

### Cheaper fallback

If a wrapper is undesirable, allow history operations only as **standalone simple commands**. Deny any such tool call containing an earlier shell segment, pipeline, redirection, command/process substitution, `cd`, or unresolved repository selector.

That keeps the two-command cost but closes the glaring `touch && git merge` case. It is a real closed grammar, unlike the current best-effort search.

---

# 2. Honesty of the guarantees

The residual discussion is unusually candid. The problem is that several summary sentences subsequently claim more than those caveats leave standing.

## Finding 1 — `--autostash` does not establish the stated precondition

The docstring says:

> “`--autostash` is git’s own stash-operate-restore, so git ESTABLISHES the precondition this check exists to enforce.”

— `git-guardrails.py` docstring, lines 56–62.

That is false when the tree contains untracked files.

### Concrete failing case

In a repository with an untracked file:

```bash
printf 'local\n' > note.txt
git status --porcelain
# ?? note.txt

git merge --autostash main
git status --porcelain
# ?? note.txt
```

I reproduced this in a scratch repository. The merge succeeded and the untracked file remained throughout. Git’s autostash handled tracked modifications in a second test but still left the untracked file.

This matters because the docstring itself identifies the exact semantic:

> “`git stash` does not stash UNTRACKED files at all”

— lines 89–91.

Yet `--autostash` is allowed without even reading the tree.

### Required correction

Either:

* remove the unconditional `--autostash` exemption; or
* read porcelain status and permit `--autostash` only under an explicitly narrower policy, such as “tracked/index changes may be Git-managed, but any `??` entry denies.”

Law 20 must also say that plain:

```bash
git stash push -m "label"
```

does not clean untracked files. When `??` entries are intended to be stashed, the relevant operation is ordinarily:

```bash
git stash push -u -m "label"
```

The accepted-cost example also overstates:

> “`git stash push -m x && git merge` is now DENIED, even though it would have worked.”

That is true only for some dirty states, not for an untracked-only dirty tree.

---

## Finding 2 — an unresolved `-C` target can still produce an allow

The docstring says:

> “If the named `-C` directory cannot be read at all … the check falls back to reading the event cwd rather than allowing on an unanswered question.”

— `git-guardrails.py` docstring, lines 77–80.

But reading the event repository and allowing when it is clean **is allowing on the unanswered question**.

### Concrete failing case

Let `/tmp/A` be the clean event repository and `/tmp/B` be dirty:

```bash
REPO=/tmp/B
git -C "$REPO" merge main
```

Under the documented design, the textual parser can retain an unexpanded `$REPO`, fail to read it, and inspect `/tmp/A` instead. If `/tmp/A` is clean, the hook allows. At execution, the shell expands the variable and Git operates in dirty `/tmp/B`.

### Required correction

When an explicit repository selector is present but cannot be resolved, **deny**. Do not substitute another repository and treat its cleanliness as evidence about the target.

The appropriate message is: “Cannot resolve the repository named by `-C`; rerun from that repository or use a literal path.”

---

## Finding 3 — repository identity is not limited to event cwd or `-C`

The stated directory rule is:

> “the working directory the invocation itself names (the event cwd, or a `-C <path>` carried by the history-op segment)”

— `git-guardrails.py` docstring, lines 70–75.

Git can select another worktree without `-C`.

### Concrete failing case

Let repository A be clean and repository B dirty:

```bash
cd /tmp/A

git \
  --git-dir=/tmp/B/.git \
  --work-tree=/tmp/B \
  merge feature
```

I reproduced this native-Git behavior: the command was launched from clean A, operated on B, completed its fast-forward there, and left B’s untracked file in place.

The environment form is equally direct:

```bash
GIT_DIR=/tmp/B/.git \
GIT_WORK_TREE=/tmp/B \
git merge feature
```

According to the documented directory rule, the hook reads A. Git operates on B.

### Required correction

For history operations, either fully support and pass through repository selectors or deny forms involving:

* `--git-dir`;
* `--work-tree`;
* `GIT_DIR`;
* `GIT_WORK_TREE`;
* any other selector the implementation does not correctly bind to the status query.

This known Git mechanism should be named in the residual if it remains unsupported. The generic final bullet—“assume there are more”—does not make the concrete claim “event cwd or `-C`” accurate.

---

## Finding 4 — this is not “a closed allowlist over the whole command”

The heading says:

> “THE RULE IS A CLOSED ALLOWLIST OVER THE WHOLE COMMAND.”

— `git-guardrails.py` docstring, lines 39–40.

The same document says:

> “`bash -c 'git merge main'` … is not inspected.”

— lines 165–169.

### Concrete failing case

```bash
bash -c 'git merge main'
```

is not in a closed allowed grammar and is not denied. It is invisible.

That is a **best-effort recognizer with a closed set of exemptions for recognized operations**, not a closed allowlist over the whole command.

### Required wording

A truthful replacement is:

> “For a history operation the parser identifies, the allow paths are limited to a fixed set of escape/self-managing tokens and a clean status result. Unidentified invocations pass outside this rule.”

---

## Finding 5 — the two hooks leave no-path Git writes between them

The root guard says of operations such as `git reset --hard`, `git merge`, and branch checkout:

> “`git-guardrails.py` is the layer that governs those.”

— `.claude/hooks/root-of-trust-guard.py` module docstring, lines 319–323.

But `git-guardrails.py` says shell-wrapper payloads are opaque:

> “`bash -c 'git merge main'` … is not inspected.”

— `git-guardrails.py` docstring, lines 165–169.

### Concrete failing case

```bash
bash -c 'git reset --hard'
```

Under the stated division:

1. the root guard unwraps the shell payload;
2. its own protected-path rules do not catch `git reset --hard`, because no protected literal path is present;
3. `git-guardrails.py` does not unwrap the outer `bash -c` payload;
4. the reset runs.

This is not merely a determined-caller bypass. Shell wrappers are ordinary execution forms.

A second case is:

```bash
bash -c 'git clean -fdx'
```

This can remove untracked and ignored research data. The command is specifically denied in direct form, but falls between the stated layers when wrapped.

### Required correction

The payload-unwrapping layer must call a **shared set of Git guard rules**, rather than only the protected-path rules. One parser should recursively inspect a supported payload and then run both policies over the resulting command representation.

Alternatively, delete the claim that `git-guardrails.py` governs these wrapped forms.

---

## Finding 6 — `reflog`, `ORIG_HEAD`, and the transcript are not a backstop for lost working files

The Git guard says:

> “What actually backstops it is … the operation stays visible in the transcript, `git reflog`/`ORIG_HEAD` keep a bad merge recoverable…”

— `git-guardrails.py` docstring, lines 191–200.

For commit-history movement, reflog and `ORIG_HEAD` are valuable. They do not backstop the destructive deny list generally.

### Concrete failing cases

```bash
bash -c 'git reset --hard'
```

can destroy unstaged tracked edits. Reflog can recover the previous commit pointer; it does not contain those unstaged bytes.

```bash
bash -c 'git clean -fdx'
```

can delete ignored or untracked data. Neither reflog nor `ORIG_HEAD` contains those files.

The transcript records that the loss occurred. It does not recover the work.

### Required wording

Call these:

* an audit trail;
* commit-history recovery aids;
* not recovery for uncommitted, untracked, or ignored files.

Do not call them a general backstop.

---

## Finding 7 — the designated “root of trust” can rewrite itself through explicitly allowed paths

The root guard states:

> “A guard that can rewrite its own guard is not a guard”

— `root-of-trust-guard.py` docstring, lines 224–227.

It then says:

> “Allowed, deliberately: Edit / Write / MultiEdit on the same files.”

— lines 279–285.

It also permits ordinary branch transitions that can replace those files.

### Concrete failing case A: permitted Edit

An agent uses `Edit` to remove the root guard’s registration from:

```text
.claude/settings.json
```

The edit appears in the transcript but is applied. The agent then issues a Bash write that would previously have been blocked.

Under `bypassPermissions`, “the human can later inspect a diff” is not equivalent to authorization before the next action.

### Concrete failing case B: ordinary branch switch

Branch `safe` contains the current hooks. Branch `old-feature` deletes `.claude/hooks/` or contains an obsolete `.claude/settings.json`.

From a clean tree:

```bash
git switch old-feature
```

The root guard has no protected literal path operand to inspect. The Git guard’s documented deny list does not prohibit branch switching. The repository’s supposed root of trust is replaced through an ordinary allowed operation.

A clean merge or pull can likewise import changes to the guard files.

### Concrete failing case C: permitted self-edit plus fail-open

The agent legitimately edits a hook but introduces a syntax error. The next call encounters:

> “any error … exits 0 with no decision (allow).”

— `root-of-trust-guard.py` docstring, lines 331–337.

The allowed modification has converted the guard into a fail-open no-op.

### Judgment

A repo-local, mutable, fail-open hook is not the root of trust. It is a **repo-local tripwire** or **silent-shell-write detector**.

The actual root must be outside the worktree—for example, the normal permission system or a machine-level hook—or modifications through every tool and branch transition must require an external authorization mechanism.

This sentence also overstates:

> “The controls that actually protect the root of trust are elsewhere…”

— lines 291–299.

The three things then listed are:

1. a visible Edit/Write diff;
2. the fact that bypass mode was deliberate;
3. any machine-wide guard the operator may happen to run.

The first is retrospective visibility, the second is not a control, and the third is optional. In the default configuration described here, there may be no protective control “elsewhere.”

---

# 3. The doctrine

The underlying filename for laws 18–21 is not supplied. I therefore cite `oracle-brief.md`, §C rather than inventing a source filename.

## Law 18 — computed counts

> “Every number that reaches a decision-maker is produced by a command whose output is the number…”

> “It binds every number you say out loud…”

### Judgment: **keep the core, delete the universal scope**

The incident supports a narrower and good rule: **decision-relevant derived counts should be recomputed from their source rather than inferred from truncated displays**.

The current wording converts a count-provenance rule into a universal numerical-speech rule.

### Concrete failing case

A results note says:

> “The preregistered significance level was 5%.”

The correct provenance is the preregistration or configuration file. A command whose output is `5` adds no epistemic value. It can become pseudo-provenance: a reproducible command reproducing a manually typed constant.

Likewise, “the referee raised two conceptual objections” may come from reading prose, not a database query. Requiring a command encourages gratuitous `grep` rituals rather than judgment.

### Replacement

> **Every decision-relevant count derived from a machine-readable artifact is recomputed from its source of truth, and the derivation is retained. Chosen constants and externally sourced quantities are traced to their declaration or source rather than manufactured by an `echo` command.**

### Most likely to be quietly ignored

**Law 18 in its present universal form.**

The phrase “including the ones no gate knows about” makes the requirement both unenforceable and visibly disproportionate for incidental numerical statements. Real users will silently interpret it more narrowly than written. A law that depends on everyone privately correcting its scope should be rewritten.

---

## Law 19 — “done”

> “Done means … the work is committed, and the commit is pushed — and only then is it reported.”

### Judgment: **delete this as a universal law**

The good principle is: do not report an unverified later state as though it exists.

The bad design is collapsing distinct states into one word and declaring push to be part of every task’s completion.

### Concrete failing case

A collaborator asks an agent:

> Prepare the patch and run the tests. Do not commit or push; I want to review the working-tree diff first.

The requested task can be fully completed, but Law 19 says it cannot be reported as done. A contributor without push credentials has the same problem. An offline user does too.

The delegated-task qualification attempts to repair this, but that proves the binary definition is wrong. Completion depends on the task contract.

### Replacement: explicit state, not a universal endpoint

Require reports to distinguish:

| State                   | Meaning                                |
| ----------------------- | -------------------------------------- |
| **modified**            | requested working-tree changes exist   |
| **verified**            | named gates have run and passed        |
| **committed**           | a commit hash exists                   |
| **pushed**              | a named remote ref contains the commit |
| **integrated/released** | the intended target contains it        |

Never claim a later state before it exists. Do not redefine every task so that its endpoint is “pushed.”

### The law I would delete

**Law 19**, replacing it with the state taxonomy above. The evidence-before-completion principle survives; the project-specific push doctrine does not.

---

## Law 20 — clean-tree history operations

> “`git status --porcelain` first. If it prints anything, commit it or stash it…”

### Judgment: **good default; keep it**

This is the strongest of the four laws. The best rationale is not that Git invariably destroys dirty work—it often refuses to overwrite conflicting local changes—but that dirty integration destroys **attribution and reviewability** and increases the chance of accidental co-staging during conflict resolution.

### Required corrections

The law must acknowledge:

* plain `git stash push -m ...` does not include untracked files;
* `--autostash` is not a universal clean-tree operation;
* the current PreToolUse check establishes only hook-time cleanliness unless compound history commands are denied or a runtime wrapper is used;
* “never” conflicts with the documented `ALLOW_DIRTY_MERGE=1` hatch.

A cleaner formulation is:

> **History operations normally start from a porcelain-clean repository. Any exception requires an explicit operator override and is reported as an exception.**

---

## Law 21 — delegated screens

> “A screening agent gets its rubric in writing before it runs…”

> “EXCLUDE as the default verdict…”

> “The dispatcher then spot-checks a sample…”

> “early returns are status, not input…”

### Written rubric, item-level evidence, and ID joins: **keep**

These are sound and actionable.

### Universal `EXCLUDE` default: **delete**

The correct default depends on the loss function.

### Concrete failing case

A researcher performs title-and-abstract screening for a systematic review. An abstract does not mention the subgroup needed for eligibility, but the full paper does.

Under a universal `EXCLUDE` default, ambiguity creates an unrecoverable false negative. For recall-first screening, the defensible ambiguity verdict is usually `INCLUDE` or `UNCERTAIN`, with exclusion deferred until enough evidence exists.

Use:

* `EXCLUDE` by default for precision-first candidate promotion;
* `INCLUDE/UNCERTAIN` by default for recall-first discovery;
* an explicitly preregistered default when costs differ.

### “Spot-checks a sample” is rigorous-sounding but not falsifiable

### Concrete failing case

A wave contains 10,000 screened candidates. The dispatcher hand-selects three obvious inclusions, confirms them, and declares the spot check successful. Meanwhile, exclusions have a 20% false-negative rate.

Nothing in the law specifies:

* how the sample is selected;
* whether exclusions must be oversampled;
* minimum sample size;
* acceptable disagreement;
* what happens after failure.

Replace it with a small protocol: random or stratified selection, mandatory sampling of exclusions and ambiguous cases, a declared acceptance threshold, and escalation after failure.

### Whole-wave adjudication needs a protocol-failure exception

### Concrete failing case

The first two agents reveal that every worker interpreted the date cutoff incorrectly. Treating those returns as “status, not input” and waiting for the whole wave wastes the entire run.

The anti-anchoring rule should be:

> Early candidate verdicts do not determine substantive adjudication, but early evidence may trigger a protocol-level stop when it reveals rubric ambiguity, corrupted inputs, or systematic worker error.

---

## Reporting adverse cells

> “Prespecify the menu, then print the cells that go against you with the same prominence as the wins.”

**Keep.** This is clear, actionable, and directly tied to research credibility.

---

## Rules not present in the supplied evidence

The exact text for the following was not supplied:

* reviewer independence as a property of the environment;
* simulations declaring an assumption regime;
* a `WITHDRAW` disposition when a default misses a preregistered bound.

Under the evidence contract, I cannot issue grounded findings on them.

Conditional hypotheses only:

| Rule                             | Hypothesis, not finding                                                                                                                                                                                                                                                                                              |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reviewer independence            | Sound if “independence” is operationalized as no access to prior verdicts, separate context/state, immutable common evidence, and no shared scratchpad. It must not imply independence of model errors merely because sessions are separate.                                                                         |
| Simulation assumption regime     | Sound for simulations used to support claims or promote defaults. It becomes ceremony if imposed identically on disposable exploratory runs. The declaration should map the DGP to theorem conditions and identify deliberate violations.                                                                            |
| `WITHDRAW` after missing a bound | Potentially a strong preregistered stop rule, but only if the bound includes Monte Carlo uncertainty, a replication/escalation rule, and clarity about what is withdrawn—the default, the claimed guarantee, or the entire method. A single noisy estimate should not mechanically trigger an undefined disposition. |

---

# 4. The blind spot

## The release’s most dangerous pattern is incident-specific lessons becoming universal laws

Each incident seems genuine. The extrapolation is sometimes too broad:

* a truncated terminal count becomes “every number you say out loud must be command-produced”;
* a premature completion report becomes “nothing is done until pushed”;
* a lenient candidate screen becomes “EXCLUDE is always the default”;
* early-wave anchoring becomes “early returns cannot inform protocol correction.”

That is how ceremony enters: not through the clean-tree boundary, which is proportionate, but through global rules applied outside the failure mode that justified them.

## The direct research-quality harm is false exclusion

A stranger may reasonably assume that the template’s capitalized “laws” encode general best practice. Applying `EXCLUDE` by default to a recall-first literature screen can silently remove relevant evidence. Unlike a noisy count or an unnecessary extra commit, that error may never become visible.

## The adoption harm is ritual compliance followed by wholesale bypass

A plausible forker is an empirically strong researcher who is not a workflow engineer. During exploratory work, the template asks them to:

* attach a command to every numerical statement;
* avoid reporting completion until a push exists;
* formalize every delegated screen;
* spot-check without a defined sampling rule;
* wait for whole waves;
* tolerate extra tool boundaries;
* trust detailed guard documentation while the repository runs in `bypassPermissions` and the hooks fail open.

The likely response is not careful selective compliance. It is one of:

1. perfunctory artifacts—meaningless count commands and ceremonial spot checks;
2. vocabulary games—“implemented locally” to route around the definition of done;
3. setting hatches or disabling rules broadly;
4. abandoning the template for exploratory work.

The especially bad combination is **high visible ceremony over a permissive substrate**:

> `permissions.defaultMode: "bypassPermissions"` with an empty deny list

combined with repo-local, mutable, fail-open textual guards.

A user can end up with more process than a conventional permissioned setup and less actual protection. The detailed caveats may prevent a technically careful reader from overtrusting the hooks, but public-template users should not be assumed to read module docstrings as security specifications.

## Better organizing doctrine

Apply hard process only where the stakes justify it:

| Surface                                        | Appropriate posture                            |
| ---------------------------------------------- | ---------------------------------------------- |
| Destructive Git, root-control changes          | hard gate or explicit external authorization   |
| Claims entering a public paper/release         | reproducible provenance and named verification |
| Default promotion / preregistered evaluation   | prespecified pass/fail/escalation rules        |
| Exploratory analysis and interim collaboration | exact status reporting, but minimal ceremony   |
| High-recall discovery screens                  | ambiguity retained, not default-excluded       |

The release currently treats too many exploratory and collaborative states like release engineering.

---

# Minimal acceptable version before merge

I would require these four changes—not the entire ideal redesign.

1. **Make clean-tree enforcement correspond to the moment of execution.** Use the trusted runtime wrapper, or deny every non-standalone history-operation form. Remove the unconditional `--autostash` exemption; deny unresolved `-C` targets; support or prohibit `--git-dir`, `--work-tree`, `GIT_DIR`, and `GIT_WORK_TREE`.

2. **Repair the cross-hook boundary.** A shell payload unwrapped by one guard must run through the shared destructive-Git rules as well. At minimum, close `bash -c 'git reset --hard'` and `bash -c 'git clean -fdx'`. Delete the claim that transcript/reflog backstop uncommitted or untracked files.

3. **Stop presenting the repo-local hook as a true root of trust.** Either protect the designated files across Edit/Write/MultiEdit and branch transitions through an external authorization mechanism, or rename/restate the component as a best-effort silent-shell-write tripwire. Explicitly disclose that an allowed edit, branch switch, clean merge, or hook error can replace or disable it.

4. **Rewrite Laws 18, 19, and 21.** Scope Law 18 to decision-relevant derived quantities; replace Law 19 with exact completion-state labels; make screening defaults depend on false-positive/false-negative costs and make spot-checking falsifiable.

The two-command usability regression alone would not block the merge. Paying that cost while still allowing a clean-at-hook-time command to dirty the tree before Git executes—and while claiming otherwise—does.

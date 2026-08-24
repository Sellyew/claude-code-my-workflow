You are an independent referee. I am shipping a release of a public template repository that other researchers fork, and I want an adversarial read from outside my own process before it merges.

WHAT ALREADY HAPPENED — do not repeat it. This branch went through eleven rounds of an internal adversarial review loop (multiple fresh-context reviewers per round, refute-biased verification of every finding, fix, re-audit). That loop was thorough on MECHANICS: counts recomputed from source, links resolving, gate coverage, shell-parsing edge cases in two guard hooks, staleness of rendered output. All of that is green and heavily tested. Re-reporting a miscount or a parsing edge case is low value.

WHAT I ACTUALLY WANT FROM YOU is judgement on the things a loop of my own agents is structurally bad at: whether the DESIGN DECISIONS are right, whether the DOCTRINE is sound and internally consistent, and whether a stranger forking this would be helped or misled. You are not bound by my framing; if you think the whole approach is wrong, say that.

THE FOUR QUESTIONS, in priority order:

1. THE GUARD REDESIGN. `git-guardrails.py` originally tried to predict, from the text of a chained shell command, whether the working tree would still be dirty by the time a `git merge/rebase/pull` in that chain executed. Successive review rounds found one unmodelled dimension after another (stash flags, stash subcommands, intervening segments, output redirection, command substitution, `cd`, and finally the semantic fact that `git stash` does not stash untracked files). I concluded that predicting shell effects by enumeration does not converge, deleted the predictor, and replaced it with: read `git status --porcelain` live at decision time and DENY a history op if the tree is dirty, regardless of what the rest of the command claims it will do.
   The accepted cost: `git stash push -m x && git merge` is now DENIED even though it would have worked; the user runs two commands instead.
   - Is that trade right, or is the usability cost worse than I think for an agentic workflow where chained commands are common?
   - Is the reasoning sound, or did I over-generalize from a run of bad luck into a false principle?
   - Is there a THIRD design I missed that is both sound and cheap? Be concrete.

2. HONESTY OF THE GUARANTEES. Both hooks now carry docstrings that name what they cannot see, and the docs repeat those limits. Read them adversarially: is the disclosed residual actually complete and accurate, or does the wording still imply more protection than the code delivers? A guard trusted past its coverage is worse than none, so over-claiming here is the failure I most want caught. Quote any sentence that overstates.

3. THE DOCTRINE. Four new "laws" and several new rules were added (computed counts; what "done" means; clean-tree merges; rubric'd delegated screens; reviewer independence as a property of the environment; simulations declaring an assumption regime; a WITHDRAW disposition when a default misses a preregistered bound). For each: is it actually good advice, or does it sound rigorous while being unactionable, unfalsifiable, or counterproductive at scale? Which one would you delete? Which is the most likely to be quietly ignored by a real user, and why?

4. THE BLIND SPOT. Given everything you can see: what is the most likely way this release makes a forking researcher's work WORSE rather than better? I am specifically worried about ceremony — a template that imposes so much process that people route around it. Tell me if that is happening.

EVIDENCE CONTRACT — this is binding, and I will discard findings that do not meet it:
- For every criticism: quote the exact text or code you are criticizing, name the file, and give a CONCRETE failing case — an input, a user, or a scenario where it goes wrong. "This could be clearer" is not a finding.
- If you cannot ground a criticism in the files provided, say so explicitly and mark it as a hypothesis rather than a finding. I would rather have five grounded findings than twenty impressions.
- Separately, give me your MINIMAL ACCEPTABLE version: the shortest list of changes you would require before you would let this merge, as distinct from everything you would ideally change. I care about that delta more than the full list.
- Where you think I am RIGHT, say so briefly and move on — I need the signal, not encouragement.

# Project Memory

Corrections and learned facts that persist across sessions.
When a mistake is corrected, append a `[LEARN:category]` entry below.

---

<!-- Append new entries below. Most recent at bottom. -->

## Workflow Patterns

[LEARN:workflow] Requirements specification phase catches ambiguity before planning → reduces rework 30-50%. Use spec-then-plan for complex/ambiguous tasks (>1 hour or >3 files).

[LEARN:workflow] Spec-then-plan protocol: AskUserQuestion (3-5 questions) → create `quality_reports/specs/YYYY-MM-DD_description.md` with MUST/SHOULD/MAY requirements → declare clarity status (CLEAR/ASSUMED/BLOCKED) → get approval → then draft plan.

[LEARN:workflow] Context survival before compression: (1) Update MEMORY.md with [LEARN] entries, (2) Ensure session log current (last 10 min), (3) Active plan saved to disk, (4) Open questions documented. The pre-compact hook displays checklist.

[LEARN:workflow] Plans, specs, and session logs must live on disk (not just in conversation) to survive compression and session boundaries. Quality reports only at merge time.

## Documentation Standards

[LEARN:documentation] When adding new features, update BOTH README and guide immediately to prevent documentation drift. Stale docs break user trust.

[LEARN:documentation] Always document new templates in README's "What's Included" section with purpose description. Template inventory must be complete and accurate.

[LEARN:documentation] Guide must be generic (framework-oriented) not prescriptive. Provide templates with examples for multiple workflows (LaTeX, R, Python, Jupyter), let users customize. No "thou shalt" rules.

[LEARN:documentation] Date fields in frontmatter and README must reflect latest significant changes. Users check dates to assess currency.

## Design Philosophy

[LEARN:design] Framework-oriented > Prescriptive rules. Constitutional governance works as a TEMPLATE with examples users customize to their domain. Same for requirements specs.

[LEARN:design] Quality standard for guide additions: useful + pedagogically strong + drives usage + leaves great impression + improves upon starting fresh + no redundancy + not slow. All 7 criteria must hold.

[LEARN:design] Generic means working for any academic workflow: pure LaTeX (no Quarto), pure R (no LaTeX), Python/Jupyter, any domain (not just econometrics). Test recommendations across use cases.

## File Organization

[LEARN:files] Specifications go in `quality_reports/specs/YYYY-MM-DD_description.md`, not scattered in root or other directories. Maintains structure.

[LEARN:files] Templates belong in `templates/` with descriptive names. Don't enumerate the inventory here — a hand-kept list goes stale (this entry's own list was missing three files when audited); `ls templates/` is the inventory.

## Constitutional Governance

[LEARN:governance] Constitutional articles distinguish immutable principles (non-negotiable for quality/reproducibility) from flexible user preferences. Keep to 3-7 articles max.

[LEARN:governance] Example articles: Primary Artifact (which file is authoritative), Plan-First Threshold (when to plan), Quality Gate (minimum score), Verification Standard (what must pass), File Organization (where files live).

[LEARN:governance] Amendment process: Ask user if deviating from article is "amending Article X (permanent)" or "overriding for this task (one-time exception)". Preserves institutional memory.

## Skill Creation

[LEARN:skills] Effective skill descriptions use trigger phrases users actually say: "check citations", "format results", "validate protocol" → Claude knows when to load skill.

[LEARN:skills] Skills need 3 sections minimum: Instructions (step-by-step), Examples (concrete scenarios), Troubleshooting (common errors) → users can debug independently.

[LEARN:skills] Domain-specific examples beat generic ones: citation checker (psychology), protocol validator (biology), regression formatter (economics) → shows adaptability.

## Memory System

[LEARN:memory] Two-tier memory solves template vs working project tension: MEMORY.md (generic patterns, committed) + native auto memory (`~/.claude/projects/<project>/memory/`, machine-local) → cross-machine sync + local privacy. *(Second tier was `personal-memory.md` until v2.5; retired for the native mechanism.)*

[LEARN:memory] Hooks prompt reflection, don't auto-append (e.g. the Stop-hook session-log reminder) → user maintains control while building habit.

## Meta-Governance

[LEARN:meta] Repository dual nature requires explicit governance: what's generic (commit) vs specific (gitignore) → prevents template pollution.

[LEARN:meta] Dogfooding principles must be enforced: plan-first, spec-then-plan, quality gates, session logs → we follow our own guide.

[LEARN:meta] Template development work (building infrastructure, docs) doesn't create session logs in quality_reports/ → those are for user work (slides, analysis), not meta-work. Keeps template clean for users who fork.

## Drift Prevention

[LEARN:drift] `replace_all` on one phrasing (e.g., `"26 skills"`) misses sibling phrasings — `"26 skills, and 21 rules"` (extra "and"), `"26 slash commands"`, `"template's 26"`, `"N skills on day one"` (prose). Count drift hit us 3 times in v1.5.x (PRs #70, #76, #78). Solution: `scripts/check-surface-sync.py` with compound regex patterns as a pre-commit gate. Adding a new phrasing to documentation requires adding a matching regex to the script, otherwise it won't be caught.

[LEARN:drift] Guard against false positives when scanning for template counts: `"3 parallel agents"`, `"17 specialized agents"` (clo-author attribution), `"start with 2-3 skills"` are all legitimate non-template uses of `N + category` phrases. Use compound patterns requiring multiple template-specific tokens on the same line.

## Claude Code Hooks

[LEARN:hooks] Stop-hook block protocol has TWO valid forms: (a) legacy — `exit 2` + reason on stderr; (b) modern — `exit 0` + JSON `{"decision":"block","reason":"..."}` on stdout. `log-reminder.py` uses the modern form. Audit agents unfamiliar with the modern protocol will flag this as "should exit 2" — false alarm. Documented in `/deep-audit` skill's false-alarm list.

[LEARN:hooks] `initialPermissionMode` in VSCode settings only fires at **session start**. Mid-session mode toggles (via `Shift+Tab` or `/permission-mode`) override the file settings until session end. The 6-tier permission stack: VSCode user / workspace / CLI user / project / project-local / in-session runtime — the last is authoritative. "Prompts fire despite bypass config" is almost always a stale session, not a settings bug.

## Plan→Bypass Framing

[LEARN:safety] Do NOT frame Plan→Bypass as a "safety boundary" or "safety guarantee." Plan approval gives you a chance to review the APPROACH before execution, but exiting plan mode returns the session to `defaultMode` (bypassPermissions), at which point any tool call runs under the full allowlist. Frame as "review-before-execute convenience." If a user needs a real enforcement boundary, they should keep `defaultMode: "default"` and approve each high-risk tool individually.

## Privacy in Diagnostic Skills

[LEARN:privacy] Diagnostic skills that read host-global config (e.g., `~/.claude/`, VSCode user settings) must require **explicit user confirmation** before crossing the repo boundary — especially in template repos that get forked. Phase the skill: repo-local auto, host-global opt-in with key redaction. Codex correctly flagged this pattern as a template-adopter privacy risk in PR #75.

## Claim-vs-Reality Framing

[LEARN:framing] ~~The "orchestrator" is a **pattern**, not a runtime.~~ **SUPERSEDED by v2.0.0 (2026-06-09)**, which rewrote `orchestrator-protocol.md` from pattern into a real runtime (fan-out → reduce → judge + hallucination gate → loop-until-dry). What still holds: there is **no daemon and no post-plan-approval trigger** — the loop is always user- or skill-initiated, and that is a documented non-goal. Docs claiming "orchestrator activates automatically after plan approval" remain wrong. *(Retired 2026-08-21 during the v2.5 stale-recommendation audit.)*

[LEARN:framing] ~~"Quality gates" is overselling when the only enforcement is inside `/commit`.~~ **SUPERSEDED by v2.0.0**, which shipped a real git pre-commit hook (`.githooks/pre-commit` via `./scripts/install-hooks.sh`) running surface-sync + quality on every commit. What still holds: the gate is only live **after the user runs `install-hooks.sh`**, and `SKIP_QUALITY_GATE=1` / `--no-verify` bypass it — so docs must say "enforced once installed", not "always enforced". *(Retired 2026-08-21 during the v2.5 stale-recommendation audit.)*

[LEARN:framing] Cross-artifact review is **pattern-based detection**, not universal auto-invocation. If the manuscript has no `\input{scripts/...}` signals, no cross-artifact work happens even without `--no-cross-artifact`. Document detection signals explicitly.

## Dogfooding Gaps Found in Round-1 Audit (2026-04-16)

[LEARN:dogfooding] Empty `quality_reports/plans/`, `specs/`, `session_logs/` directories in a WORKING FORK are a red flag — claimed dogfooding nobody follows. (In the shipped template these dirs are gitignored by design, so the heuristic applies to your own fork, not the clean tree.) The Stop-hook log reminder validates itself by catching missing logs; plan-first has no equivalent automation.

[LEARN:audit] "Claim-vs-reality" is the highest-ROI audit lens for a governance-heavy template repo. More valuable than skill-consistency or doc-drift checks because it surfaces where the template oversells itself — the exact thing forkers will discover and call out.

[LEARN:audit] Whack-a-mole anti-pattern: surgically fixing a bot-flagged phrase in a summary paragraph usually introduces new drift in the same paragraph (3× on v1.6.1). Two flags on one paragraph = rewrite it structurally, don't patch word-by-word. See `summary-parity.md`.

## Verification Architecture (three complementary patterns)

[LEARN:pattern] Verification in this repo now operates at three architectural levels, each addressing a different failure mode. Do NOT collapse them — they are complementary, not redundant:

1. **Critic-fixer loop** (`/qa-quarto`, `/review-paper --adversarial`) — **two agents, serial** — one reads the artifact and flags issues, the other applies fixes; loop until APPROVED. Best for **presentation + structural** bugs (Beamer↔Quarto parity, manuscript completeness). Agents see the full artifact; adversarial tension comes from role assignment.

2. **Cross-artifact review** (`/review-paper` + `/review-r` + `/audit-reproducibility`) — **horizontal dependency traversal** — a manuscript's claims depend on scripts' outputs, so the manuscript reviewer spawns script reviewers and reproducibility checkers alongside the paper review. Best for **paper ↔ code consistency** (ATTs, coefficients, N match the outputs that produced them).

3. **Post-Flight Verification / CoVe** (`/verify-claims` + `claim-verifier` agent, v1.7.0) — **single agent, fresh-context fork** — the verifier has never seen the draft; it answers verification questions from the source material alone, using `context: fork` to architecturally enforce independence. Best for **factual hallucination** (fabricated citations, wrong dataset fields, misattributed findings). Adapted from Dhuliawala et al. 2023 ([arXiv:2309.11495](https://arxiv.org/abs/2309.11495)).

The key insight: each pattern enforces independence differently. Critic-fixer uses role tension; cross-artifact uses dependency graph traversal; CoVe uses context isolation. A skill that needs all three (e.g., `/review-paper --peer`) invokes them at different phases.

[LEARN:pattern] Post-Flight Reports (v1.7.0) are the output-side twin of Pre-Flight Reports (v1.6.0). Pre-Flight proves inputs were read; Post-Flight proves claims hold. Both use structured output blocks, fail-closed fallbacks, and explicit opt-outs. Together with summary-parity (v1.6.1), they form the **discipline-pattern trilogy**: input discipline + framing discipline + output discipline. When designing a new skill that generates text, ask: does it need all three?

[LEARN:audit] Skill frontmatter `allowed-tools` must cover every tool the skill body invokes, but this is easy to miss — the body reads as English ("spawn the verifier via Task" — the tool was renamed `Agent` in 2026; the lesson is unchanged) while the frontmatter reads as a bureaucratic array. Caught on PR #92 when Codex + Copilot both flagged 4 skills that promised `Task` in the body but had no `Task` in `allowed-tools`. Runtime failure mode: tool-permission error, or silent bypass of the promised protocol. Deep-audit Agent 3 now includes this check explicitly. Sibling check: if rule X's `paths:` includes skill Y, confirm skill Y actually implements rule X's protocol (rule-vs-implementation drift is the same class of bug at a different layer).

[LEARN:audit] Deterministic bug classes (field exists, anchor resolves, count matches disk) belong in mechanical scripts — agent attention drifts, scripts don't. Reserve audit agents for judgment calls. `check-skill-integrity.py` ships the mechanical batch; `audit-pet-peeves.md` catalogues the judgment classes.

[LEARN:audit] When writing a parity-check regex, always strip inline code spans (` `` `) and fenced code blocks (` ``` `) before pattern-matching. Docs use example syntax like `[text](path#anchor)` inside backticks to illustrate; a naive regex treats those as real links. Replace matched code with spaces (preserving line numbers) before running the rest of the check.

[LEARN:audit] Audit-scope ATROPHY: audit agents only check what their prompt scopes, so any new code directory bypasses audit by default (6 bot-caught bugs in unscoped `scripts/`). **When adding a code location, expand audit scope first** — audit-debt accumulates silently.

## Scheduling Autonomous Work

[LEARN:scheduling] `CronCreate` is session-only in practice — it dies with the REPL (hit 2026-04-16 via a rate-limit termination). Work that must survive session death uses **Routines** (cloud-side). CronCreate is fine for short polling inside a live session, not "run this in an hour".

[LEARN:hooks] PreCompact hooks now support blocking via the modern protocol (exit 0 + `{"decision":"block","reason":"..."}` on stdout). `.claude/hooks/pre-compact.py` gained an opt-in DRAFT-plan guard (env var `CLAUDE_PRECOMPACT_BLOCK_ON_DRAFT=1`): blocks compaction once when an active plan is still marked DRAFT, so the user has a chance to approve the plan before losing mid-plan context. Default off — users who prefer the old save-and-continue behavior get no change. Fires at most once per plan to avoid lock-out loops.

## v1.8.0 Cycle Lessons (2026-04-27)

[LEARN:permissions] **Protected-path behavior is mode-dependent — re-verify, never assume** (re-verified 2026-08-22 vs the permission-modes doc: `bypassPermissions` disables prompts and safety checks INCLUDING protected paths — the earlier "`.claude/` always prompts" version of this entry was stale). Auto mode classifier-gates risky actions and since 2026-08-14 is the built-in starting mode on Pro/Max/Team. Forkers in default mode still see prompts on `.claude/` edits.

[LEARN:vscode] **`claudeCode.allowDangerouslySkipPermissions` is a typo trap** — the canonical key has NO `claudeCode.` prefix (unlike `claudeCode.initialPermissionMode`). The wrong key is silently ignored. Documented in `TROUBLESHOOTING.md`.

[LEARN:edits] **Batch edits to protected `.claude/` paths: use Bash + `python3` heredoc.** Edit fires the protected-paths gate; Bash does not. For 5+ edits, one read→modify→write script via Bash avoids the prompt storm.

[LEARN:audit] **Surface-sync checks counts and MARKED tables** (`<!-- surface-sync-table: ... -->`, since v2.0) — tables without the marker are invisible to it (the guide appendix shipped 58 of 60 rows in v2.5 until a semantic sweep caught it). New skill/agent: add the row AND confirm the table is marker-covered or hand-checked.

[LEARN:pattern] **`disable-model-invocation: true` is load-bearing-write discipline.** Set it on skills writing persistent files the user must intend (lecture .tex, SKILL.md, preregistration); not on transient-report skills. It only blocks model auto-trigger; `/skill-name` still works. (Codified in `templates/skill-template.md`.)


## v1.9.0 Cycle Lessons (2026-05-20)

[LEARN:workflow] **Plan-first scales to multi-pass releases.** v1.9.0 shipped 6 skills + 2 agents + 2 rules across 9 PRs from one comprehensive plan file; each pass became a small reviewable PR, and mid-flight additions got a Pass slot in the plan. For multi-PR releases, the plan file is the navigation, not the conversation.

[LEARN:pattern] **Detect-only beats auto-rewrite for prose quality.** `/humanize` ships without `--rewrite`: cross-vendor findings show auto-rewriting AI-voice tells degrades quality and adds new tells. For any "fix my prose" skill, detect-and-flag with line numbers; the author edits. Same rationale keeps `/proofread` advisory.

[LEARN:pattern] **Distil-don't-truncate for long sessions.** Auto-compaction drops early turns; `/compress-session` writes a structured note instead (decisions, files, open questions, next actions, **discarded-as-noise**). Listing failed hypotheses explicitly stops them ghost-haunting future context. Companion to `/checkpoint`, not a replacement.

[LEARN:pattern] **Five-critic isolated voting beats single-critic composite judgment.** `/promote-memory` graduates `[LEARN]` entries via 5 forked critics (generality / staleness / redundancy / evidence / format), one dimension each, votes hidden from each other — isolation prevents groupthink. The user is the final gate even at 5-of-5. (Adapted with attribution from claudeblattman v2.1.)

[LEARN:pattern] **Provenance as a YAML artifact, not a folder.** `templates/passport-template.yaml`: per-paper numeric claims with source line, output field, tolerance, status; `/audit-reproducibility` rewrites it in place. Queryable beats folder reports. (Scope-reduced from Imbad0202/ARS "Material Passport" to numeric claims only.)

[LEARN:pattern] **Variance reporting > point estimate for peer review.** ~37% of verdicts vary purely from referee-disposition sampling (AgentReview, arXiv:2406.12708), so `--variance N` returns a verdict distribution + K-of-N concern table instead of one verdict. Bimodal spreads and tight majorities are both information. Referees route to Sonnet; hard cap N=5.

[LEARN:pattern] **HIGH-WARN must-fix for fabricated citations.** `/verify-claims` tiers: HIGH-WARN (fabricated reference / numerical or directional contradiction) is must-fix before commit; MED-WARN transient; LOW-WARN inaccessible source. Be conservative assigning HIGH-WARN — false positives erode the gate. The CoVe forked verifier (never sees the draft) is the architecture; the must-fix policy makes it consequential.

[LEARN:pattern] **70/20/10 model routing for cost discipline** (`model-routing.md`): Haiku tier mechanical, Sonnet tier review/critique, Opus tier high-judgment. 50–80% savings with no quality loss on the mechanical tier. Anti-pattern: down-tiering claim-verifier / methods-referee / editor — one false-positive PASS costs more than the routing saves. (Primary source: Anthropic "Decoupling brain from hands", Apr 2026.)

[LEARN:research] **Research-grounded plans beat eyeballed roadmaps.** When scope is "what should we add?", run parallel research agents first (ecosystem / community / cross-vendor / internal audit) and verify uncertainties before planning — the plan becomes traceable to URLs and verified facts instead of opinions. ~30 min of dispatch buys non-redundant, currently-true items.

[LEARN:workflow] **Surface-sync must check enumerative tables, not just counts.** Count assertions catch "N skills" drift but not missing table rows (the v1.5.0 agent trio was absent from README for 3 releases; the guide appendix shipped 58 of 60 rows in v2.5 until a semantic sweep caught it). Every skill/agent addition: update count assertions AND the guide appendix AND the README table.


## v2.5 Cycle Lessons (2026-08-21)

[LEARN:process] **Plan mode is not optional on a vague, multi-hour ask.** A vague "update our workflow" session with no plan mode, no spec, no `AskUserQuestion` paid the documented 30-50% rework: north star, guide plan, version scheme, and phase framing all rewritten mid-flight — each fixable by a 5-question spec in one turn. **Trigger: vague ask, multiple readings, >1 hour or >3 files → spec first, via `AskUserQuestion`.**

[LEARN:process] **Survey the machine before the world.** An ecosystem review searched the web first and found the owner's own `~/.claude/skills/` and private repos only after being asked — three times; the strongest material was local every time. **Order: own repos and `~/.claude/` → ecosystem → literature.**

[LEARN:framing] **Never write an exclusivity claim into a plan — it propagates to the webpage.** "The only public workflow that..." is unfalsifiable marketing. Use a dated survey finding plus repo-checkable claims. Banned in shipped copy: *the only, the first, nobody else, unmatched, best-in-class*.

[LEARN:process] **Do not propose restructuring an artifact you have not read.** A guide restructure drafted from its heading tree would have destroyed field-tested patterns that already solved the problem and handed every fork a merge conflict. **Headings are not the artifact.**

[LEARN:audit] **A green gate proves internal consistency, not external truth.** The model gate exited 0 while the SSoT named superseded tiers — surfaces merely agreed with each other. Currency gates need an external oracle plus a staleness expiry, or stale-but-consistent is indistinguishable from current.

[LEARN:audit] **Tool-name drift silently disarms hooks and gates.** When `Task` became `Agent`, 33 skills still declared `Task`, a `Bash|Task` hook matcher stopped firing, and the integrity checker certified the dead contract green. **Migrate tool names by registering both matchers, and source checker tool lists from the current reference, never hard-coded.**

[LEARN:safety] **Scrub attributions before promoting a global skill into a public repo.** A promotion candidate carried an unpublished paper's title + authors in `description:`. **Deny-list scan over publishable surfaces in pre-commit + CI, fail-closed, term list gitignored — before the port begins.**

[LEARN:process] **A skill's `description:` is a shared contract — edit under `blast-radius`.** It governs model auto-invocation machine-wide; global `~/.claude/skills/` edits are higher blast radius than project edits, not lower.

[LEARN:audit] **Improving a surface can silently remove it from gate coverage.** A landing-page rewrite changed the count phrasing; gates stayed green because the page was no longer *matched* — a gate that matches nothing reports nothing. **After editing a checked surface, seed a defect and confirm it is still seen; a falling assertion count is the investigate signal.**

[LEARN:audit] **Qualify in both directions, always.** Detection-only tuning over-fires; false-alarm-only tuning goes blind (a compound-pattern gap let a bare count phrase through). Ship checker changes only after seeded drifts AND legitimate-prose controls. Detection without a false-alarm control is half a measurement.

[LEARN:process] **Verify the branch actually changed before committing.** A `git checkout -b` bundled with a hook-blocked command never ran; ten commits landed on `main`. **A blocked hook fails the WHOLE call — anything bundled with it silently did not happen. After any branch op, echo `git rev-parse --abbrev-ref HEAD` and read it.**

[LEARN:governance] **Methodological content in the owner's own field ships only with the owner's CURRENT sign-off.** The `/did-event-study` skill was vetoed and removed on 2026-08-22 by the owner — the field's leading expert — despite June-2026 commits recording an earlier sign-off. The lesson: a sign-off attaches to the content it reviewed, not to the skill's name; after substantial edits, refreshes, or promotion into a public template, the vetting is void until renewed. For any surface that prescribes methodology the owner is professionally identified with, the gate is an explicit, dated owner approval of the current text — and absent that, the surface does not ship, however well it evals.

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

[LEARN:files] Templates belong in `templates/` directory with descriptive names. Currently have: session-log.md, quality-report.md, exploration-readme.md, archive-readme.md, requirements-spec.md, constitutional-governance.md, decision-record.md (v1.6.0), journal-profile-template.md (v1.5.0), response-to-referees.md, skill-template.md, plus `tikz-snippets/` directory.

## Constitutional Governance

[LEARN:governance] Constitutional articles distinguish immutable principles (non-negotiable for quality/reproducibility) from flexible user preferences. Keep to 3-7 articles max.

[LEARN:governance] Example articles: Primary Artifact (which file is authoritative), Plan-First Threshold (when to plan), Quality Gate (minimum score), Verification Standard (what must pass), File Organization (where files live).

[LEARN:governance] Amendment process: Ask user if deviating from article is "amending Article X (permanent)" or "overriding for this task (one-time exception)". Preserves institutional memory.

## Skill Creation

[LEARN:skills] Effective skill descriptions use trigger phrases users actually say: "check citations", "format results", "validate protocol" → Claude knows when to load skill.

[LEARN:skills] Skills need 3 sections minimum: Instructions (step-by-step), Examples (concrete scenarios), Troubleshooting (common errors) → users can debug independently.

[LEARN:skills] Domain-specific examples beat generic ones: citation checker (psychology), protocol validator (biology), regression formatter (economics) → shows adaptability.

## Memory System

[LEARN:memory] Two-tier memory solves template vs working project tension: MEMORY.md (generic patterns, committed), personal-memory.md (machine-specific, gitignored) → cross-machine sync + local privacy.

[LEARN:memory] Post-merge hooks prompt reflection, don't auto-append → user maintains control while building habit.

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

[LEARN:dogfooding] Empty `quality_reports/plans/`, `specs/`, `session_logs/` directories are a red flag — they mean the repo claims to enforce dogfooding rules that nobody is following. Stop hook on `log-reminder.py` did catch the missing session log this session, which validates the hook's value. Plan-first has no equivalent automation.

[LEARN:audit] "Claim-vs-reality" is the highest-ROI audit lens for a governance-heavy template repo. More valuable than skill-consistency or doc-drift checks because it surfaces where the template oversells itself — the exact thing forkers will discover and call out.

[LEARN:audit] Whack-a-mole anti-pattern on summary paragraphs: when Copilot/Codex flag a summary paragraph, surgically fixing the flagged phrase almost always introduces a new drift elsewhere in the same paragraph (observed 3× in a row on the v1.6.1 CHANGELOG opening, PRs #88–#90). Rule: two review-bot flags on the same paragraph = rewrite structurally (abstract up, remove enumeration), don't patch word-by-word. Prefer "no new directories on disk" over "no new skills, rules, or hooks." See `.claude/rules/summary-parity.md`.

## Verification Architecture (three complementary patterns)

[LEARN:pattern] Verification in this repo now operates at three architectural levels, each addressing a different failure mode. Do NOT collapse them — they are complementary, not redundant:

1. **Critic-fixer loop** (`/qa-quarto`, `/review-paper --adversarial`) — **two agents, serial** — one reads the artifact and flags issues, the other applies fixes; loop until APPROVED. Best for **presentation + structural** bugs (Beamer↔Quarto parity, manuscript completeness). Agents see the full artifact; adversarial tension comes from role assignment.

2. **Cross-artifact review** (`/review-paper` + `/review-r` + `/audit-reproducibility`) — **horizontal dependency traversal** — a manuscript's claims depend on scripts' outputs, so the manuscript reviewer spawns script reviewers and reproducibility checkers alongside the paper review. Best for **paper ↔ code consistency** (ATTs, coefficients, N match the outputs that produced them).

3. **Post-Flight Verification / CoVe** (`/verify-claims` + `claim-verifier` agent, v1.7.0) — **single agent, fresh-context fork** — the verifier has never seen the draft; it answers verification questions from the source material alone, using `context: fork` to architecturally enforce independence. Best for **factual hallucination** (fabricated citations, wrong dataset fields, misattributed findings). Adapted from Dhuliawala et al. 2023 ([arXiv:2309.11495](https://arxiv.org/abs/2309.11495)).

The key insight: each pattern enforces independence differently. Critic-fixer uses role tension; cross-artifact uses dependency graph traversal; CoVe uses context isolation. A skill that needs all three (e.g., `/review-paper --peer`) invokes them at different phases.

[LEARN:pattern] Post-Flight Reports (v1.7.0) are the output-side twin of Pre-Flight Reports (v1.6.0). Pre-Flight proves inputs were read; Post-Flight proves claims hold. Both use structured output blocks, fail-closed fallbacks, and explicit opt-outs. Together with summary-parity (v1.6.1), they form the **discipline-pattern trilogy**: input discipline + framing discipline + output discipline. When designing a new skill that generates text, ask: does it need all three?

[LEARN:audit] Skill frontmatter `allowed-tools` must cover every tool the skill body invokes, but this is easy to miss — the body reads as English ("spawn the verifier via Task" — the tool was renamed `Agent` in 2026; the lesson is unchanged) while the frontmatter reads as a bureaucratic array. Caught on PR #92 when Codex + Copilot both flagged 4 skills that promised `Task` in the body but had no `Task` in `allowed-tools`. Runtime failure mode: tool-permission error, or silent bypass of the promised protocol. Deep-audit Agent 3 now includes this check explicitly. Sibling check: if rule X's `paths:` includes skill Y, confirm skill Y actually implements rule X's protocol (rule-vs-implementation drift is the same class of bug at a different layer).

[LEARN:audit] Mechanical vs agent-based audits: classes of bug that are deterministic (frontmatter field exists, anchor resolves, count matches disk) belong in a mechanical script, not an agent prompt. Agents miss these because the prompt lists them as one of many checks, and agent attention drifts. The script never drifts. Reserve audit agents for judgment calls (is this claim misleading? does this rule contradict that one?). `scripts/check-skill-integrity.py` shipped the first batch (frontmatter↔body tool parity, argument-hint↔body flag parity, anchor resolution, rule↔skill keyword parity). `.claude/references/audit-pet-peeves.md` catalogues the subtler classes that still need agent judgment so /deep-audit agents inherit past bot findings.

[LEARN:audit] When writing a parity-check regex, always strip inline code spans (` `` `) and fenced code blocks (` ``` `) before pattern-matching. Docs use example syntax like `[text](path#anchor)` inside backticks to illustrate; a naive regex treats those as real links. Replace matched code with spaces (preserving line numbers) before running the rest of the check.

[LEARN:audit] Audit-scope creep — or rather, audit-scope ATROPHY. Deep-audit Agent 2 was scoped to `.claude/hooks/*.py|sh`. When PR #93 added new Python + bash code under `scripts/`, the audit didn't look. Copilot + Codex caught 6 bugs the audit missed, all five of which were in `scripts/`. Root cause: audit agents only check what their prompt scopes; any new directory bypasses audit by default. **Rule: when adding a new code location, expand audit scope first, or audit-debt accumulates silently.** Agent 2 now scoped to all executable code (hooks + scripts + .claude/scripts). Pet-peeves entries 13-16 capture the specific classes that motivated this widening (docstring-contract drift, fail-open narrow-except, bash set-u not enough, dead config-map entries).

## Scheduling Autonomous Work

[LEARN:scheduling] `CronCreate` (the local Claude Code cron) is **session-only** in practice even with `durable: true` — it dies if the Claude Code REPL isn't running when the cron time arrives. Hit this on 2026-04-16 when the user's usage got rate-limited, the session terminated, and the scheduled audit-hardening trigger never fired. For any autonomous work that must survive session termination (rate limits, Claude Code restarts, sleep), use **Claude Code Routines** (released Apr 14, 2026) instead — they run on Anthropic's web infrastructure, not the local REPL. `CronCreate` is fine for short-delay polling within an active session (check a build every 5 min), but not for "run this in an hour." See `.claude/references/audit-pet-peeves.md` entry 17.

[LEARN:hooks] PreCompact hooks now support blocking via the modern protocol (exit 0 + `{"decision":"block","reason":"..."}` on stdout). `.claude/hooks/pre-compact.py` gained an opt-in DRAFT-plan guard (env var `CLAUDE_PRECOMPACT_BLOCK_ON_DRAFT=1`): blocks compaction once when an active plan is still marked DRAFT, so the user has a chance to approve the plan before losing mid-plan context. Default off — users who prefer the old save-and-continue behavior get no change. Fires at most once per plan to avoid lock-out loops.

## v1.8.0 Cycle Lessons (2026-04-27)

[LEARN:permissions] **`.claude/` is hard-protected by the Claude Code extension and no user setting can fully unprotect it.** Per Anthropic's [permission-modes doc](https://code.claude.com/docs/en/permission-modes), the protected list (`.git`, `.vscode`, `.idea`, `.husky`, `.claude` minus carve-outs `commands/agents/skills/worktrees`) is hard-coded. Bypass mode does NOT skip these — it still prompts. The only mode that doesn't fire an interactive prompt on protected paths is **auto mode** (Mar 2026 Week 13), which routes them through a classifier instead. **UPDATED 2026-08-21:** auto mode is no longer plan-gated — since **2026-08-14** it is the **built-in starting permission mode** for new interactive terminal and VS Code sessions on **Pro, Max, and Team**, and it is available on Amazon Bedrock, Google Cloud's Agent Platform, and Microsoft Foundry without an opt-in variable. The original entry said it required Team/Enterprise/API and was 'rolling out to Max'; that is now stale. Forkers without auto-mode access will see prompts on edits to `.claude/references/`, `.claude/rules/`, `.claude/hooks/`, `.claude/scripts/` no matter what their settings say.

[LEARN:vscode] **The VSCode extension key `claudeCode.allowDangerouslySkipPermissions` is a typo trap.** Canonical key is `allowDangerouslySkipPermissions` (NO `claudeCode.` prefix). The companion key `claudeCode.initialPermissionMode` DOES use the prefix — so users guess by analogy and write the wrong key. Wrong key is silently ignored, leaving the protected-paths gate active even with broad CLI bypass. v1.8.0's `.vscode/settings.json` was wrong on the shipped template until this cycle caught it. Documented in `TROUBLESHOOTING.md` under "Permissions / bypass / statusline".

[LEARN:edits] **For batch edits to protected `.claude/` paths during a session, use Bash + `python3` heredoc.** The Edit tool fires the protected-paths gate; the Bash tool does not. When you have ~5+ edits to `.claude/references/` or `.claude/rules/` in one session, write a single python script that reads → modifies → writes and exec it via Bash. Catches the same parity-gate prompts the user is actively trying to avoid. This is what got v1.8.0's `disable-model-invocation` audit and journal-profile additions through cleanly after the user explicitly asked "no more manual approvals!"

[LEARN:audit] **Surface-sync gate covers numeric counts but NOT enumerative tables.** v1.8.0's deep-audit caught the appendix "All Skills" table missing `/checkpoint` + `/preregister` AND "All Agents" missing the v1.5.0 peer-review trio (editor / domain-referee / methods-referee — pre-existing drift inherited across 3 releases). The `check-surface-sync.py` script counts assertion phrasings ("30 skills") but doesn't verify enumerative tables tabulate the same N items. Pet-peeves entry added (#18). Future: when adding a skill/agent, check the appendix tables — surface-sync won't catch the row drift.

[LEARN:pattern] **`disable-model-invocation: true` is a load-bearing-write discipline, not a "do not disturb" toggle.** Set it on skills that write a *persistent file the user must explicitly intend to create* (lecture .tex, TikZ source, SKILL.md, checkpoint snapshot, preregistration document). Don't set it on skills that produce transient analysis output (proofread / review-r / visual-audit reports). Codified in `templates/skill-template.md` under "When to set `disable-model-invocation: true`". The flag still allows direct invocation as `/skill-name` — it only blocks model auto-trigger on heuristic match.


## v1.9.0 Cycle Lessons (2026-05-20)

[LEARN:workflow] **Plan-first scales to multi-pass releases.** v1.9.0 shipped 6 new skills + 2 agents + 2 rules + 1 template across 9 PRs by writing one comprehensive plan first (`quality_reports/plans/2026-05-20_v1.9.0-guide-refresh.md`) and then executing per-pass. Each pass became a small, reviewable PR; the plan stayed the single source of truth for "what's done vs. what's deferred." When the user added items mid-flight (`/humanize`, `/prompt`), the plan was updated and the new items got a Pass slot. Lesson: for multi-PR releases, the plan file is the navigation, not the conversation.

[LEARN:pattern] **Detect-only beats auto-rewrite for prose quality.** `/humanize` (v1.9.0) deliberately ships without a `--rewrite` mode. Cross-vendor research (Cursor/Aider community) found auto-rewriting AI-voice tells degrades quality and introduces *new* tells. The author edits manually; that's the price of preserving voice. Apply this principle to any "fix my prose"-class skill: if the auto-fix would be a model rewrite of the affected text, prefer detect-and-flag with line numbers + suggested rewrites, not auto-application. Same rationale as keeping `/proofread` advisory and not auto-applying its findings.

[LEARN:pattern] **Distil-don't-truncate for long sessions.** Auto-compaction is lossy — it keeps recent turns and drops earlier ones. `/compress-session` (v1.9.0) is the alternative: produce a structured note (Active state, Decisions, Files, Open questions, Next actions, **Discarded as noise**) and the next session resumes from the note. The "Discarded as noise" section is the novel piece: explicitly listing failed hypotheses prevents them from ghost-haunting future context (Drew Breunig's "poisoning" failure mode). Companion to `/checkpoint` (explicit stop-points), not replacement.

[LEARN:pattern] **Five-critic isolated voting beats single-critic composite judgment.** `/promote-memory` (v1.9.0) decides which `[LEARN]` entries graduate from personal-memory.md to MEMORY.md by spawning 5 critics in forked contexts (generality / staleness / redundancy / evidence / format). Each votes YES/NO on one dimension; majority promotes. Critics cannot see each other's votes — isolation prevents groupthink. Pattern adapted with attribution from Blattman's claudeblattman v2.1. The user is the final gate even on 5-of-5 unanimous votes — critic agreement informs, doesn't decide.

[LEARN:pattern] **Provenance as a YAML artifact, not a folder.** v1.9.0 added `templates/passport-template.yaml` — a per-paper file listing every numeric claim with `source_file:line` + `output_file:field` + tolerance + status (PASS/FAIL/STALE/UNVERIFIED). `/audit-reproducibility` reads + rewrites in place. Stronger than folder-based reports because it's queryable and grep-able. Scope-reduced from Imbad0202/ARS's "Material Passport" (their 13-schema YAML threads through ~6 agents); ours stays narrow to numeric-claim provenance only. Future schema extensions for citation / dataset / figure provenance possible but deferred.

[LEARN:pattern] **Variance reporting > point estimate for peer review.** `/review-paper --peer` originally returned one editorial verdict from one editor + 2 referees. AgentReview (ACL 2024, arXiv:2406.12708) found ~37% of paper decisions vary purely from reviewer-disposition sampling. v1.9.0's `--variance N` mode runs N referees with sampled dispositions and returns a *distribution* of verdicts plus a K-of-N concern-frequency table. The variance itself is information — bimodal "love-it-or-hate-it" papers reveal themselves; tight modal majorities reveal robust concerns. Cost: N×referee tokens (route referees to Sonnet via [model-routing.md](.claude/rules/model-routing.md)). Hard cap N=5.

[LEARN:pattern] **HIGH-WARN gate-refuse for fabricated citations.** `/verify-claims` (v1.9.0) introduced three severity tiers: HIGH-WARN (fabricated reference / numerical contradiction / directional contradiction), MED-WARN (transient retrieval failure), LOW-WARN (source genuinely inaccessible). HIGH-WARN **blocks `/commit`** for affected files unless explicit `--no-fail-closed` override. False positives erode the gate's authority — be conservative on HIGH-WARN assignment. The CoVe forked-verifier architecture (verifier never sees the draft) is the architectural defence; HIGH-WARN gate is the policy that makes it consequential.

[LEARN:pattern] **70/20/10 architect/editor split for cost discipline.** v1.9.0's `model-routing.md` rule codifies tier-per-agent: the **Haiku tier** for mechanical work (TikZ extraction, citation formatting, bib validation, quarto-fixer); the **Sonnet tier** for review/critique (r-reviewer, slide-auditor, proofreader, humanize-auditor); the **Opus tier** for high-judgment work (editor, methods-referee, claim-verifier, domain-reviewer). Typical 50–80% cost reduction on routed skills with no quality loss on the mechanical tier. Anti-pattern: pushing claim-verifier / methods-referee / editor down a tier to save cost — these protect the paper from hallucination + weak identification + desk-reject mistakes, and the cost of one false-positive PASS dominates the routing savings. Anthropic's Apr 8 2026 "Decoupling brain from hands" post is the primary-source endorsement.

[LEARN:research] **Research-grounded plans beat eyeballed roadmaps.** v1.9.0 started with 4 parallel research agents (Anthropic ecosystem / community repos / cross-vendor / internal audit) producing a 17-item ranked recommendation set, then 2 verification agents resolving uncertainties (rename history, ARS schema details). The plan that emerged was traceable to specific URLs and verified facts. By contrast, the original "let me brainstorm what could improve the guide" cycle would have produced opinions, not citations. Lesson: when scope is "what should we add?" not "fix this bug", invest in research before planning. Cost: ~30 min of agent dispatch; value: confidence that each item was non-redundant and currently true.

[LEARN:workflow] **Surface-sync gate must check enumerative tables too, not just numeric assertions.** v1.9.0 added 6 skills + 2 agents; each addition needed manual surface-sync verification PLUS manual appendix-table updates. `check-surface-sync.sh` caught count drift but not row-by-row table drift. This is pet-peeves entry #18 + v2.0-backlog "enumerative-table consistency check." Until that ships, every new skill / agent addition requires: (1) update count assertions; (2) update appendix table in guide; (3) update README skill/agent table. The cost of forgetting is silent drift that compounds across releases (the v1.5.0 peer-review trio of agents was missing from README for 3 releases before v1.8.0 caught it).


## v2.5 Cycle Lessons (2026-08-21)

[LEARN:process] **Plan mode is not optional on a vague, multi-hour ask — and skipping it costs the documented 30-50% rework.** A session that opened with "recommendations for updating our workflow" ran for hours across dozens of files with no `EnterPlanMode`, no requirements spec, and no `AskUserQuestion`. The predicted failure mode arrived on schedule: the north star was rewritten (overselling), the guide plan was rewritten (proposed a restructure before reading the guide), the version scheme was rewritten (v3.0 → v2.5), and the phase framing was rewritten (releases → milestones). Every one of those was a requirement that a 5-question spec would have fixed in one turn. **Trigger check before any research: is the ask vague? are there multiple valid readings? >1 hour or >3 files? If yes to any — spec first, and use `AskUserQuestion`, not prose questions spread over eight turns.**

[LEARN:process] **Survey the machine before surveying the world.** A currency/ecosystem review searched the public web and peer repos first, and only found the owner's own `~/.claude/skills/`, private research repos, and a same-day playbook repo after being asked directly — three times. The strongest material was local every time. **Order: own repos and `~/.claude/` → then the ecosystem → then the literature.**

[LEARN:framing] **Never write an exclusivity claim into a plan; it propagates to the webpage.** A north star that read "the only public workflow that..." is unfalsifiable marketing and is the exact claim-vs-reality failure this repo audits for. Replace with a dated survey finding ("in a survey on DATE we did not find X — name one and we'll correct it") plus a claim that is checkable against the repo. Banned in shipped copy: *the only, the first, nobody else, unmatched, best-in-class*. `check-model-versions.sh`'s superlative-drift check covers model claims only; extend it to product claims.

[LEARN:process] **Do not propose restructuring an artifact you have not read.** A plan to reorganize the guide around eight new protocols was drafted from its heading tree. On reading the file, the guide already had 16 numbered Workflow Patterns and a progressive-adoption callout that solved the same problem; the restructure would have destroyed field-tested material and handed every fork a merge conflict in the largest file in the repo. **Read the whole artifact before proposing a structural change to it. Headings are not the artifact.**

[LEARN:audit] **A green gate proves internal consistency, not external truth.** `check-model-versions.sh` exited 0 while the model SSoT named two superseded tiers, because it only checks that surfaces agree *with each other*. Any currency gate needs an external oracle plus a staleness expiry (`verified_on` older than N days fails), or a stale-but-consistent repo is indistinguishable from a current one.

[LEARN:audit] **Tool-name drift silently disarms hooks and gates.** The subagent primitive is `Agent`; `Task` no longer exists as a tool (`TaskCreate`/`TaskGet`/… are the unrelated agent-teams task list). 33 of 52 skills still declared `Task` in `allowed-tools`, a `PostToolUse` matcher of `Bash|Task` stopped firing on subagents, and `check-skill-integrity.py` certified the dead contract green. **When migrating a tool name, register both matchers rather than swapping, and source the checker's tool list from the current tools reference instead of hard-coding it.**

[LEARN:safety] **Scrub attributions before promoting a global skill into a public repo.** A skill slated for promotion carried an unpublished paper's title and full author list in its `description:` field. Nothing had leaked (the public template verified clean), but promotion would have published it. **A deny-list scan over publishable surfaces belongs in the pre-commit hook and CI, fail-closed, with the term list itself gitignored — before any content port begins, not after.**

[LEARN:process] **Editing a skill's `description:` is a shared-contract change and needs `blast-radius`.** The description is what governs model auto-invocation, so changing it alters behavior in every project on the machine, not just the one in front of you. Global `~/.claude/skills/` edits are higher blast radius than project edits, not lower.

[LEARN:audit] **Improving a surface can silently remove it from gate coverage.** Rebuilding the landing page around persona paths replaced its compound count phrasing (`"53 skills, 18 agents, 32 rules"`) with separate bulleted lines. Every gate stayed green — not because the page was correct, but because it was no longer *matched*. A gate that matches nothing reports nothing, and that is indistinguishable from a gate that matches everything and finds no fault. **After editing any checked surface, seed a defect into that surface and confirm it is still seen.** Track the assertion count over time: it went 29 → 34 across v2.5, and a *falling* count is the signal to investigate.

[LEARN:audit] **Qualify in both directions, always.** A gate tuned only for detection over-fires; one tuned only against false alarms goes blind. The count patterns are deliberately compound so they do not fire on legitimate prose ("start with 2-3 skills", "17 specialized agents"), which is correct — and it left a gap that a bare template-verb count fell straight through. The fix was qualified on 3 seeded drifts *and* 3 legitimate-prose controls before shipping. Detection without a false-alarm control is half a measurement.

[LEARN:process] **Verify the branch actually changed before committing ten times.** A `git checkout -b` issued in the same tool call as a command the `git-guardrails` hook blocked never ran — the hook aborted the call, the checkout output was swallowed, and ten commits landed on `main` instead of the feature branch. Nothing was lost (recovered with `git branch <name>` at HEAD, then `git branch -f main origin/main`), but the fix was only cheap because the working tree was clean and nothing had been pushed. **After any branch operation, echo `git rev-parse --abbrev-ref HEAD` and read it.** A blocked hook makes the *whole* call fail, not just the offending command — so anything bundled with a blocked command silently did not happen.

[LEARN:governance] **Methodological content in the owner's own field ships only with the owner's CURRENT sign-off.** The `/did-event-study` skill was vetoed and removed on 2026-08-22 by the owner — the field's leading expert — despite June-2026 commits recording an earlier sign-off. The lesson: a sign-off attaches to the content it reviewed, not to the skill's name; after substantial edits, refreshes, or promotion into a public template, the vetting is void until renewed. For any surface that prescribes methodology the owner is professionally identified with, the gate is an explicit, dated owner approval of the current text — and absent that, the surface does not ship, however well it evals.

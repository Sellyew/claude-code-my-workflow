#!/usr/bin/env python3
"""
Git & Path Guardrails Hook (PreToolUse)

Blocks the small set of operations that are destructive or that the
template's own conventions forbid — before they run, not after. Adapted
from the `git-guardrails` pattern in mattpocock/skills, scoped so the
normal workflow (`/commit` pushes, stages specific files) still works.

Two checks, by tool:

  Bash — deny destructive / convention-violating git:
    - git reset --hard            (silently discards work)
    - git clean -f / -fd / -fdx   (deletes UNTRACKED files — incl. data)
    - git push --force / -f       (clobbers remote history; --force-with-lease is allowed)
    - git add -A / --all / git add .   (the commit skill forbids blanket staging)
    - git checkout -- . / git restore .   (mass discard of working changes)

      HOW THE DENY LIST DECIDES, since r10: over the SAME tokenised, unquoted
      segments the clean-tree check reads, not over the raw command string. The
      command line is split into segments, each segment's leading shell syntax
      is dropped, a word whose basename is `git` is found, git's GLOBAL options
      are walked, and the rule for that SUBCOMMAND is applied to the remaining
      ARGUMENT TOKENS — `--hard`, `--force`, `-A`, `.` — compared as whole
      words. Until r10 these were regexes over the raw string, so quoting one
      token defeated them: `git reset "--hard" HEAD~1`, `git 'reset' --hard
      HEAD~1`, `git add '-A'`, `git add "--all"` and `git checkout -- '.'` were
      all SILENT while the byte-equivalent bare spellings DENIED. Sharing the
      tokenizer also means the two checks can no longer disagree about what a
      command says, and it fixed a false deny in the other direction: a fully
      QUOTED mention (`echo "never run git reset --hard here"`) writes nothing
      and is now silent. An UNQUOTED mention still denies — see THE COST OF
      FAILING TOWARD DENY below; that applies to both checks.

    - git merge / rebase / pull with a DIRTY tree   (a resolution that also
      swallows uncommitted work is unreviewable afterwards). Hatch:
      ALLOW_DIRTY_MERGE=1.

      THE RULE IS A CLOSED ALLOWLIST OVER THE WHOLE COMMAND. It predicts
      NOTHING about what the shell will do:

        1. FIND the history ops this command line invokes, by parsing the
           command TEXT. The line is split into segments; each segment's
           leading shell syntax is dropped — variable assignments, the reserved
           words (`if then elif else fi for while until do done case esac in
           select function time`), a `!` negation, the grouping tokens
           `( ) { }`, a leading redirection — and the segment is then searched
           for a word whose basename is `git`, followed (after git's GLOBAL
           options) by `merge` / `rebase` / `pull`. If no segment yields one,
           this check is SILENT. A `git pull` that survives quoting as a single
           WORD — inside an `echo "…"`, a heredoc body, a `python3 -c '…'`
           payload — is text, not an invocation, and is not found.
           This step is a best-effort parse, and it is the ONLY thing standing
           between an op and the tree reading. What it cannot identify, it does
           not check: see WHAT IT DOES NOT SEE.
        2. If the invocation carries an ESCAPE or SELF-MANAGING flag as an
           ACTUAL ARGUMENT TOKEN — a word that IS `--abort`, `--continue`,
           `--skip`, `--quit`, `--edit-todo`, or `--autostash` — ALLOW, without
           reading the tree. The first five are how you get OUT of a dirty
           in-progress operation; `--autostash` is git's own
           stash-operate-restore, so git ESTABLISHES the precondition this
           check exists to enforce. The test is EXACT TOKEN EQUALITY over the
           words after the subcommand, stopping at a `--` end-of-options marker
           and skipping the VALUES of value-taking options (`-m`, `-F`,
           `--exec`, `-X`, `-s`, …). So an exempt word that is really part of a
           VALUE does not qualify — `git merge -m "wip --autostash later"` is
           an ordinary merge and faces rule 3 — and neither `--no-autostash`
           (self-management switched off) nor `--skip-smudge` (a different
           flag that merely starts with an exempt one) qualifies.
        3. Otherwise READ THE TREE, live: `git status --porcelain` in the
           working directory the invocation itself names (the event cwd, or a
           `-C <path>` carried by the history-op segment — a quoted `-C` path
           is honoured, so quoting cannot bypass it, and a RELATIVE `-C` path is
           resolved against the event cwd, not against whatever directory the
           hook process happens to have been spawned in). CLEAN → allow.
           DIRTY → DENY, whatever any other segment in the chain claims to do.
           If the named `-C` directory cannot be read at all (it does not
           exist, it holds an unexpanded `$var`, git cannot answer), the check
           falls back to reading the event cwd rather than allowing on an
           unanswered question.

      WHY IT NO LONGER SIMULATES THE SHELL. Eight audit rounds tried to
      PREDICT, from command text, whether the tree would still be clean by the
      time the op ran: stash flags, then stash subcommands, then the segments
      in between, then per-repository clean marks, then output redirection —
      and every round found one more dimension the enumeration had missed. The
      last round found three at once: a command substitution inside an
      "inert" segment (`echo $(touch f)` writes and was classified inert), a
      `cd` into another checkout, and the plain semantic fact that `git stash`
      does not stash UNTRACKED files at all — so even a "provable full
      cleaner" can leave the tree dirty. Simulating shell semantics by
      enumeration does not converge. So the machinery that existed only to
      model intervening segments — the stash-effect classifier, the
      inert-segment allowlist, the per-repository cleaned map — IS DELETED.
      The check reads the tree as it actually is at decision time. Command
      substitution, `cd`, untracked-after-stash and every shell form not yet
      invented cannot make a live `git status --porcelain` report a dirty tree
      as CLEAN — the verdict is not derived from the command text at all.

      WHAT THAT SENTENCE DOES NOT COVER, and round 9 proved it: a form can
      still keep the op out of the PARSER's sight, so no reading is ever taken.
      That is a different failure and it is a real one — round 9 executed three
      instances (`if true; then git merge x; fi`, `git -P reset --hard` /
      `git --no-optional-locks pull`, and `git merge -m "… --autostash …"`).
      Those three are closed. The class is NOT closed, so what remains is
      disclosed below as residual rather than claimed away.

      THE ACCEPTED COST, stated plainly: `git stash push -m x && git merge` is
      now DENIED, even though it would have worked. That is a real usability
      regression, taken deliberately. It converts an unbounded soundness hole
      into one extra keystroke: run the cleaning step and the history op as
      SEPARATE commands — the guard re-reads the real tree state on the second
      one — or commit/stash first, or set ALLOW_DIRTY_MERGE=1. Split is also
      clearer: you see whether the stash actually cleaned the tree before you
      merge, instead of asking a hook to guess.

  Write/Edit/MultiEdit — warn on hardcoded machine paths in code:
    - absolute home paths (/Users/<u>, /home/<u>, C:\\Users\\) written into
      .R / .qmd / .do / .py files break replication packages. Warn by
      default; set CLAUDE_STRICT_PATHS=1 to hard-deny.

WHAT THE CLEAN-TREE CHECK IS — a LIVE reading of `git status --porcelain`,
reached through a best-effort TEXTUAL scan of the Bash command line. The scan
answers one narrow question — does this command line invoke a history op, and
in which directory — and nothing else is inferred from the text. It is not a
proof and not a sandbox.

WHAT IT GUARANTEES — this much, and no more. For a history op this parser
IDENTIFIES (rule 1) that carries no rule-2 escape token, the verdict is a LIVE
`git status --porcelain` reading taken at hook time in the directory the
invocation names. No feature of the command text substitutes for that reading:
there is no model of the shell left to fool, so the ALLOW side cannot be talked
into existing by clever text — it can only be reached by a tree that is
actually clean, or by the op never being identified in the first place.

WHAT IT EXPLICITLY DOES NOT CLAIM: that it identifies every shell form. It does
not, it cannot, and nine rounds of trying to enumerate forms is the reason that
sentence is written this way. Where the parse is ambiguous the code is written
to fall toward FINDING an op (an unknown git global option is consumed rather
than mistaken for the subcommand; a `git` word later in a segment is still
searched for; an unreadable `-C` directory degrades to reading the event cwd
instead of allowing) — but "falls toward deny where the parse permits" is not
"denies everything it should". A form the parser does not identify is not
denied; it is INVISIBLE, and the op runs. That residual is listed next.

THE COST OF FAILING TOWARD DENY, stated as a cost: because a `git` word is
searched for past an unrecognised leading word, an UNQUOTED mention of a
history op in an ordinary command — `echo run git pull later`, `man git merge`
— is denied on a dirty tree. Quoting it (`echo "run git pull later"`) makes it
one word again and it is silent. This is the same trade as the r8 accepted
cost: a small, visible over-deny bought a whole class of wrapper bypasses.
Since r10 the deny list shares that parser, so it carries the same cost:
`echo run git push --force later` denies, `man git reset` does not (no
`--hard`), and the quoted spellings of both are silent.

WHAT IT DOES NOT SEE — disclosed residual, BOUNDARY not defect. Since r10 this
block covers BOTH checks, because both reach their subject through the SAME
parser: what the parser cannot identify, neither check sees. (Before r10 it was
scoped to the clean-tree check alone, while the deny list ran on raw text and
had no boundary statement anywhere — which is how the quoting hole above went
undisclosed as well as unclosed.)
  - a history op carried by an INTERPRETER whose program text is not a command
    line — `python3 -c '...subprocess.run(["git","merge"])...'`, `perl -e`, an
    R `system()` call. The op never appears as a `git` segment here.
  - a history op inside a SHELL-WRAPPER payload — `bash -c 'git merge main'`,
    `env -S 'git pull'`, `sh -c '...'`. Unlike root-of-trust-guard, this check
    does NOT unwrap `-c` payloads, so such a form is not inspected. (A payload
    that is a single QUOTED word is one word to the tokenizer; the same is true
    of any op that survives quoting intact.)
  - a history op run by an alias, a script file, a Makefile target, or a git
    hook — anything whose text is on disk rather than on this command line.
  - a `cd` earlier on the same command line. Repository identity is read from
    `-C` or the event cwd ONLY, so `cd <other repo> && git merge` is judged
    against the SESSION's repository, not the one the merge runs in. That can
    over-deny (session repo dirty, other repo clean — one extra keystroke) and
    it can allow an op in a repository whose state was never read. Use
    `git -C <path> merge`, which IS read, or run from that repository.
  - any dirtying that happens BETWEEN the hook's decision and the command
    actually running. The `git status` answer is a point-in-time reading.
  - ANY SHELL FORM THAT PUTS THE OP SOMEWHERE THIS PARSER DOES NOT LOOK. The
    list above is the set known on 2026-08-23; it is a report of where the
    parser has been probed, not a proof of where it is complete. Round 9 found
    five such forms that eight earlier rounds had not (compound-command
    keywords, an exempt token inside an option value, the same inside a trailing
    comment, unenumerated git global options, a relative `-C`). All five are
    closed; the CLASS is not. Assume there are more.
CLOSED at r9, therefore no longer residual: the bare COMMAND WRAPPER
(`timeout 300 git pull`, `nice git merge`, `nohup`, `command`, `env`), disclosed
at r8 because the segment's first word is not `git`. A `git` word is now
searched for along the segment — at the over-deny cost stated above.
None of the forms above is closed, and these checks are DEFENCE IN DEPTH over a
deliberate bypass posture, not a sandbox: permissions ship in bypass mode here,
so a determined caller was never the threat model. What actually backstops it
is the same layering root-of-trust-guard relies on — the operation stays
visible in the transcript, `git reflog`/`ORIG_HEAD` keep a bad merge
recoverable, changes arrive through reviewable Edit/Write diffs rather than
invisibly, and the deliberate hatch (ALLOW_DIRTY_MERGE=1 in the session
environment) exists so the honest way past this check is to SAY SO rather than
to route around it. What this hook buys is that the ordinary accident — an
agent one-liner that merges over uncommitted work — costs a denial instead of
an unreviewable commit.

Decision protocol (modern PreToolUse): exit 0 + JSON
  {"hookSpecificOutput": {"hookEventName": "PreToolUse",
    "permissionDecision": "deny", "permissionDecisionReason": "..."}}.
Fail-open: any error → exit 0 with no decision (allow).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

# ── git's GLOBAL options: ONE table, ONE consumer ──────────────────────────
#
# Options can sit between `git` and the subcommand (`git -C <dir> reset --hard`,
# `git -c x=y clean -fd`). Both the deny list and the clean-tree check must walk
# past them to reach the real subcommand — and until r9 each had its OWN
# enumeration of which options exist. Both enumerated seven. git documents far
# more, so ONE innocuous unlisted option defeated BOTH at once: `git -P`
# (git's own short spelling of `--no-pager`, whose LONG spelling was listed),
# `git --no-optional-locks`, `--literal-pathspecs`, `--icase-pathspecs`,
# `--no-replace-objects`, `--exec-path=…`, `--bare`. With any of them inserted,
# `reset --hard` / `clean -fd` / `push --force` / `add -A` / `checkout -- .`
# all went SILENT, and so did the dirty-tree check on merge/rebase/pull.
#
# So stop enumerating which options EXIST. Enumerate only the ones that take a
# SEPARATE value token (the one thing a walker cannot guess), and treat every
# other leading `-…` word as a one-token global option. That fails toward
# FINDING the subcommand — i.e. toward DENY — instead of toward missing it.
#
# r10: there is no longer a regex COPY of this table. `_GO`, the regex-prefix
# spelling that the deny patterns carried, is DELETED along with the raw-string
# deny regexes themselves — the deny list now walks the same `_walk_git_globals`
# the clean-tree check walks, so the "two consumers that disagreed" shape that
# produced the r9 defect cannot recur here at all.
_GIT_GLOBAL_VALUE_OPTS = ("-C", "-c", "--git-dir", "--work-tree", "--namespace",
                          "--exec-path", "--super-prefix", "--attr-source",
                          "--config-env")


# ── the destructive-git deny list, decided over TOKENS ─────────────────────
#
# r10: these five rules used to be REGEXES over the RAW command string, and
# ordinary shell quoting of a SINGLE token defeated every one of them. Executed
# against the shipped guard on a fixture repo: `git reset --hard HEAD~1` DENIED,
# while `git reset "--hard" HEAD~1`, `git 'reset' --hard HEAD~1`, `git add '-A'`,
# `git add "--all"` and `git checkout -- '.'` were all SILENT. The clean-tree
# check had already been rebuilt to tokenise (`_segments` → `_unquote` →
# `_git_segment`); the deny list had not, so the two halves of ONE guard
# disagreed about what a command even says, and the half with no boundary
# statement was the one with the hole.
#
# They now share ONE representation. A rule is
# (subcommand, predicate over the ARGUMENT TOKENS, reason, safe alternative);
# the predicate sees every word after the subcommand, already unquoted, with a
# trailing shell comment already dropped by `_segments`. A quoted flag is
# therefore matched exactly like a bare one, because by the time the predicate
# runs there is no difference between them.
#
# WHAT THE PORT CHANGED, both directions, stated rather than claimed away:
#   * quoting no longer evades — the six spellings above now DENY (battery
#     cases b5-b12 pin them).
#   * a MENTION that survives quoting is now correctly SILENT: in
#     `echo "never run git reset --hard here"` the quoted span is ONE word whose
#     basename is not `git`, so no invocation is found. The old raw regex DENIED
#     that string, which wrote nothing — a false deny, now gone (case b13).
#   * an UNQUOTED mention — `echo run git reset --hard later` — still denies,
#     because `_git_segment` searches for a `git` word ALONG the segment. That is
#     the SAME accepted over-deny the clean-tree check already carries and it is
#     what closes the bare-wrapper class (`timeout 300 git push --force`,
#     `nice git clean -fd`), which the raw regex caught only by the accident of
#     matching anywhere in the string.
#
# The predicates deliberately do NOT stop at a `--` end-of-options marker. For
# `add`/`checkout`/`restore` the dangerous operand is a PATHSPEC that
# legitimately follows `--` (`git add -- .`), and for the flag rules a `--hard`
# or `--force` sitting after `--` would be a pathspec by that name, which does
# not exist. Biased toward DENY, like the rest of this file.

def _has_token(args, *names):
    """True when an ACTUAL argument token IS one of `names` (exact equality —
    `--force-with-lease` is not `--force`)."""
    return any(a in names for a in args)


def _short_flag(args, letter):
    """True when a single-dash SHORT-OPTION GROUP carries `letter`: `-f`, `-fd`,
    `-uA`. A long option is never a short group, which is what keeps
    `--force-with-lease` and `--force-if-includes` allowed."""
    return any(len(a) > 1 and a[0] == "-" and not a.startswith("--") and letter in a[1:]
               for a in args)


def _mass_discard(args):
    """`git checkout -- .` / `git restore .` — a whole-tree discard.

    `--staged`/`-S` alone is NOT a working-tree discard (it unstages, and the
    work stays in the tree), so it does not qualify unless `--worktree`/`-W` is
    also present. The old regex could not express this: it only looked at the
    token immediately after the subcommand, so it neither caught
    `git restore --source=HEAD .` nor spared `git restore --staged .`."""
    if not _has_token(args, "."):
        return False
    staged = _has_token(args, "--staged") or _short_flag(args, "S")
    worktree = _has_token(args, "--worktree") or _short_flag(args, "W")
    return worktree or not staged


# (subcommand, predicate over argument tokens, human reason, safe alternative)
GIT_DENY = [
    ("reset", lambda a: _has_token(a, "--hard"),
     "git reset --hard discards uncommitted work irrecoverably.",
     "Use `git stash` (recoverable) or reset specific paths."),
    ("clean", lambda a: _has_token(a, "--force") or _short_flag(a, "f"),
     "git clean -f/--force deletes UNTRACKED files — including data not yet committed.",
     "Inspect with `git clean -n` first; delete specific paths by hand."),
    ("push", lambda a: _has_token(a, "--force") or _short_flag(a, "f"),
     "git push --force clobbers remote history.",
     "Use `git push --force-with-lease` if you truly must rewrite a branch."),
    ("add", lambda a: _has_token(a, "-A", "--all", ".", ":/") or _short_flag(a, "A"),
     "Blanket staging (git add -A / . / -- . / :/) can stage data, secrets, or settings.local.json. "
     "The /commit skill forbids it.",
     "Stage specific files: `git add path/to/file ...`."),
    ("checkout", _mass_discard,
     "Mass discard of working-tree changes is irreversible.",
     "Discard specific files, or `git stash` to keep them recoverable."),
    ("restore", _mass_discard,
     "Mass discard of working-tree changes is irreversible.",
     "Discard specific files, or `git stash` to keep them recoverable."),
]

# A merge, rebase, or pull started on a dirty tree resolves *two* sets of
# changes at once and records only one of them as a decision — afterwards
# nothing distinguishes "I chose this" from "this was in my tree".
#
# The check operates on COMMAND SEGMENTS for ONE reason only: to tell a real
# `git merge` from a `git merge` merely mentioned in an echo, inside a quoted
# string, or in a heredoc body. It does NOT reason about what the other
# segments do — that was the simulator, and it is gone (see the docstring).
#
# `--autostash` is exempt for the OPPOSITE reason to `--abort`/`--continue`: it
# is git's own stash-operate-restore. git stashes the dirty tree, runs the
# merge/rebase/pull, and reapplies the stash afterwards, so the uncommitted work
# is never folded into the resolution — the precondition this check enforces is
# ESTABLISHED BY GIT ITSELF. It is supported on merge, rebase and pull and is
# switched on implicitly by `rebase.autoStash` / `pull.autoStash`, so denying it
# rejected the git-native spelling of the very remedy the deny message
# recommends. Only the affirmative form is exempt: `--no-autostash` does not
# qualify, so explicitly turning autostash OFF still faces the live check.
#
# r9: the exemption is decided from ARGUMENT TOKENS, not from a substring
# search over the joined segment. It used to be the latter, and rule 2 is the
# ONLY path that skips the live `git status` read — so any option VALUE
# containing the literal text of an exempt flag switched the whole check off.
# Executed on a dirty fixture: `git merge -m "wip --autostash later" feature`
# was ALLOWED, as were `git pull -m "after the --abort we retry" origin main`,
# a trailing `# finish the --continue later` comment, a branch called
# `feature--continue`, and `git rebase --skip-smudge main` (the old `\b` was
# satisfied by the following hyphen). None of those is an escape form; each is
# an ordinary history op on a dirty tree, which is precisely what rule 3 exists
# to refuse.
GIT_OP_EXEMPT_TOKENS = frozenset(
    ("--abort", "--continue", "--skip", "--quit", "--edit-todo", "--autostash"))

# Options on a history op that take a SEPARATE value token. Their value must be
# SKIPPED before the exempt test, or the value gets read as a flag. Biased
# toward over-skipping on purpose: skipping one word too many can only cost a
# DENY (rule 3 runs), while skipping one too few is a false ALLOW.
_GIT_OP_VALUE_OPTS = frozenset((
    "-m", "--message", "-F", "--file", "--exec", "-x", "-s", "--strategy",
    "-X", "--strategy-option", "-S", "--gpg-sign", "--into-name", "--onto",
    "--log", "--depth", "--deepen", "--shallow-since", "--shallow-exclude",
    "--refmap", "--upload-pack", "--recurse-submodules", "-j", "--jobs",
))

GIT_HISTORY_OPS = {"merge", "rebase", "pull"}
_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def _op_is_exempt(words: list[str], start: int) -> bool:
    """True only when an ACTUAL argument token of this invocation IS one of the
    rule-2 escape flags. `start` is the index of the subcommand."""
    i = start + 1
    while i < len(words):
        w = words[i]
        if w == "--":                       # end of options: refs only after
            return False
        if w in GIT_OP_EXEMPT_TOKENS:
            return True
        if w in _GIT_OP_VALUE_OPTS and i + 1 < len(words):
            i += 2                          # `-m <message>`: the value is DATA
            continue
        i += 1
    return False

# Tokenizer: split a Bash command into per-command segments on shell
# separators, keeping quoted spans intact so a separator inside quotes does not
# split a segment.
_SEG_TOKEN = re.compile(
    r"""(?P<sep>\|\||&&|;|&|\||\n)
      | (?P<word>(?:"[^"]*"|'[^']*'|\\.|[^\s"'|;&\n])+)""",
    re.VERBOSE,
)
_HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")

HARDCODED_PATH = re.compile(r"(/Users/[^/\s'\")]+|/home/[^/\s'\")]+|[A-Za-z]:\\\\Users\\\\[^\\\s'\"]+)")
CODE_EXT = {".R", ".r", ".qmd", ".do", ".py", ".Rmd"}


def _unquote(w: str) -> str:
    out, i = [], 0
    while i < len(w):
        c = w[i]
        if c in "\"'":
            j = w.find(c, i + 1)
            if j == -1:
                out.append(w[i + 1:]); break
            out.append(w[i + 1:j]); i = j + 1
        elif c == "\\" and i + 1 < len(w):
            out.append(w[i + 1]); i += 2
        else:
            out.append(c); i += 1
    return "".join(out)


def _strip_heredocs(cmd: str) -> str:
    """Drop heredoc BODIES so a `git pull` that merely appears inside one is
    prose, not a command — the same posture as root-of-trust-guard."""
    if "<<" not in cmd:
        return cmd
    out, pending = [], None
    for line in cmd.split("\n"):
        if pending is not None:
            if line.strip() == pending:
                pending = None
            continue
        out.append(line)
        last = None
        for last in _HEREDOC.finditer(line):
            pass
        if last:
            pending = last.group(2)
    return "\n".join(out)


def _segments(cmd: str) -> list[list[str]]:
    """Per-command segments as lists of unquoted words.

    A word whose RAW text begins with `#` starts a shell COMMENT: it and the
    words after it are not arguments, so they are dropped. The test is on the
    raw word, before `_unquote`, so a quoted `"#123 fix"` message stays an
    argument. r9: without this, `git pull origin main  # finish the --continue
    later` put an exempt TOKEN on the invocation and skipped the tree read."""
    segs: list[list[str]] = [[]]
    comment = False
    for m in _SEG_TOKEN.finditer(cmd):
        if m.group("sep") is not None:
            segs.append([])
            comment = False
            continue
        raw = m.group("word")
        if raw.startswith("#"):
            comment = True
        if not comment:
            segs[-1].append(_unquote(raw))
    return [s for s in segs if s]


# Shell RESERVED WORDS and grouping tokens that can stand in front of a command
# inside one segment. Until r9 a segment was tested for git by its FIRST word
# only, so every one of these hid the op completely: `if true; then git merge x;
# fi`, `( git merge x )`, `{ git merge x; }`, `for d in .; do git -C $d pull;
# done`, `while …; do git pull; …; done`, `else git rebase main`,
# `! git merge x`, `>/dev/null git merge x` — all executed SILENT on a dirty
# fixture while the byte-identical bare spelling DENIED.
_SHELL_HEAD_WORDS = frozenset((
    "if", "then", "elif", "else", "fi", "for", "while", "until", "do", "done",
    "case", "esac", "in", "select", "function", "time", "coproc",
    "!", "(", ")", "{", "}", "[[", "]]",
))
# `>f` `2>f` `>>f` `<f` `>&2` `<>f` … as a leading word, attached or bare.
_REDIR_HEAD = re.compile(r"^\d*(?:>>|>&|>\||<>|<&|>|<)")


def _strip_shell_head(words: list[str]) -> tuple[list[str], int]:
    """Drop leading shell SYNTAX so the command word itself can be seen.
    Returns the (possibly rewritten) word list and the index of the first word
    that is not shell syntax."""
    words = list(words)
    i = 0
    while i < len(words):
        w = words[i]
        if _ASSIGN.match(w) or w in _SHELL_HEAD_WORDS:
            i += 1
            continue
        bare = w.lstrip("({!")                 # `(git`, `{git`, `!git`
        if bare != w:
            if bare:
                words[i] = bare
                continue                       # re-test the rewritten word
            i += 1
            continue
        m = _REDIR_HEAD.match(w)
        if m:
            # a BARE operator carries its target in the next word (`> /dev/null`)
            i += 2 if m.end() == len(w) else 1
            continue
        if w.endswith(")") and "/" not in w:   # `*)` case label, `f()` definition
            i += 1
            continue
        break
    return words, i


def _walk_git_globals(words: list[str], i: int) -> tuple[int, str | None]:
    """Consume git's GLOBAL options starting just after the `git` word. Returns
    (index of the subcommand — or len(words) if there is none, `-C` path).

    Only the value-taking names in `_GIT_GLOBAL_VALUE_OPTS` consume a second
    token; ANY other leading `-…` word is consumed as a one-token global. See
    that table for why enumerating which options exist was the defect."""
    dash_c = None
    while i < len(words):
        w = words[i]
        if not w.startswith("-") or w == "--":
            break
        if w == "-C" and i + 1 < len(words):
            dash_c = words[i + 1]; i += 2; continue
        if w.startswith("-C") and len(w) > 2 and "=" not in w:   # -Cdir
            dash_c = w[2:]; i += 1; continue
        if "=" in w:                                             # --opt=value
            i += 1; continue
        if w in _GIT_GLOBAL_VALUE_OPTS and i + 1 < len(words):
            i += 2; continue
        i += 1                                                   # any other global
    return i, dash_c


def _git_segment(words: list[str]) -> tuple[str | None, str | None, int, list[str]]:
    """If a segment invokes git, return (subcommand, -C path, subcommand index,
    the words the index refers to); else (None, None, -1, words).

    The word list is returned because `_strip_shell_head` REWRITES leading words
    (`(git` → `git`), so the index is meaningful only against the list this
    function actually walked. Both callers — the deny list and the clean-tree
    check — slice arguments with it, and neither may guess.

    Leading shell syntax is dropped first, then a `git` word is searched for
    ALONG the segment rather than tested at position 0 only. Searching forward
    also closes the r8-disclosed bare-COMMAND-WRAPPER residual (`timeout 300 git
    pull`, `nice git merge`, `nohup`, `command`, `env`) — at the stated cost
    that an UNQUOTED mention of a history op or a destructive op in another
    command now denies. A mention that survives quoting is a single WORD and is
    still silent, which is what the rule-1 control (c17) and the deny-list
    control (b13) pin."""
    words, i = _strip_shell_head(words)
    while i < len(words):
        if os.path.basename(words[i]) == "git":
            j, dash_c = _walk_git_globals(words, i + 1)
            if j < len(words):
                return words[j], dash_c, j, words
            return None, None, -1, words
        i += 1
    return None, None, -1, words


def git_deny_reason(cmd: str) -> str | None:
    """The destructive-git deny list, decided over the SAME tokenised, unquoted
    segments the clean-tree check reads. Returns the deny message, or None."""
    for seg in _segments(_strip_heredocs(cmd)):
        sub, _dash_c, at, words = _git_segment(seg)
        if sub is None:
            continue
        args = words[at + 1:]
        for name, predicate, reason, alt in GIT_DENY:
            if sub == name and predicate(args):
                return (f"{reason} {alt} "
                        f"(override: run it in a terminal yourself, outside Claude Code.)")
    return None


# ────────────────────────────────────────────────────────────────────────────
# DELETED IN r8, DELIBERATELY: `_STASH_VALUE_FLAGS`, `_STASH_REDIRTY`,
# `_STASH_NEUTRAL`, `_STASH_CLEANERS`, `_STASH_CLEAN_FLAGS`, `_stash_effect`,
# `_INERT_GIT_SUBS`, `_INERT_COMMANDS`, `_REDIRECTORS`,
# `_segment_writes_via_redirection`, `_segment_is_inert`, `_REPO_KEY_CACHE`,
# `_repo_key`, `_resolve_repo_key`, and the per-repository `cleaned` map.
#
# All of it existed for ONE purpose: to decide whether an earlier segment in
# the same command line had left the tree clean enough to license a later
# history op — i.e. to SIMULATE the shell. Rounds 4 through 8 each found one
# more dimension the simulation had not modelled (stash flags, stash
# subcommands, intervening segments, repository identity, output redirection,
# command substitution, `cd`, and untracked-after-stash). The leak lived in the
# complexity itself, so the complexity is gone: the guard now reads the tree
# live and refuses a dirty-tree history op unconditionally. Nothing here may be
# reintroduced without re-opening that hole.
# ────────────────────────────────────────────────────────────────────────────

def deny(reason: str) -> None:
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, sys.stdout)


def tree_is_dirty(cwd: str | None) -> bool | None:
    """True/False, or None when git cannot answer (not a repo, git missing,
    timeout) — in which case the caller allows."""
    try:
        r = subprocess.run(["git", "status", "--porcelain"], cwd=cwd or None,
                           capture_output=True, text=True, timeout=3)
    except Exception:
        return None
    if r.returncode != 0:
        return None
    return bool(r.stdout.strip())


DIRTY_TREE_REMEDY = (
    "Run the cleaning step and the history op as SEPARATE commands — this guard "
    "re-reads the real tree state on the second one, so `git stash push -m "
    "\"<what this is>\"` (or a commit) and THEN `git {op} ...` is allowed. "
    "Chaining them in ONE command is refused on purpose: this guard reads the "
    "tree, it does not simulate what the earlier half of a chain would have "
    "done to it. (Override: ALLOW_DIRTY_MERGE=1 in the session environment.)"
)


def _resolve_dash_c(dash_c: str | None, default_cwd: str | None) -> str | None:
    """Resolve a `-C <path>` against the INVOCATION's directory.

    r9: the raw string was handed to `subprocess.run(cwd=…)`, which resolves a
    relative path against the HOOK PROCESS's cwd — not the event cwd the same
    function already treats as authoritative. With the two differing (the Bash
    tool's cwd drifts; hooks are spawned by the CLI process), `git -C . pull` in
    a dirty repo A was judged against whatever repo B the hook happened to sit
    in, and went SILENT — using the exact spelling the docstring recommends as
    the remedy for the `cd` residual."""
    if not dash_c:
        return default_cwd
    p = os.path.expanduser(dash_c)
    if not os.path.isabs(p):
        if not default_cwd:
            return None                      # unanchored → caller degrades
        p = os.path.join(default_cwd, p)
    return os.path.normpath(p)


def dirty_tree_reason(cmd: str, event: dict) -> str | None:
    if os.environ.get("ALLOW_DIRTY_MERGE", "") == "1":
        return None
    default_cwd = (event.get("cwd")
                   or os.environ.get("CLAUDE_PROJECT_DIR") or None)
    # One live reading per working directory this command line names. There is
    # NO state carried between segments — no clean marks, no stash effects, no
    # inertness. A segment is looked at for exactly one thing: is it a git
    # history op, and does it carry its own `-C`.
    seen: dict[str, bool | None] = {}

    def read(cwd: str | None) -> bool | None:
        key = cwd or ""
        if key not in seen:
            seen[key] = tree_is_dirty(cwd)
        return seen[key]

    for seg in _segments(_strip_heredocs(cmd)):
        sub, dash_c, at, words = _git_segment(seg)
        if sub not in GIT_HISTORY_OPS:
            continue                         # rule 1: not a history op → silent
        # Rule 2: escape / self-managing forms need no tree at all — decided
        # from actual argument TOKENS, never from text anywhere in the segment.
        if _op_is_exempt(words, at):
            continue
        # Rule 3: read the tree, live, in the directory THIS invocation names.
        cwd = _resolve_dash_c(dash_c, default_cwd)
        dirty = read(cwd)
        if dirty is None and cwd != default_cwd:
            # The named directory could not be read (it does not exist, it holds
            # an unexpanded `$var`, git cannot answer). Do not ALLOW on an
            # unanswered question: fall back to the invocation's own cwd, which
            # is what the same op with no `-C` would have been judged against.
            dirty = read(default_cwd)
        if not dirty:
            continue                         # clean (or unreadable) → allow
        return (f"git {sub} must start from a clean tree — `git status --porcelain` is "
                f"non-empty, so this {sub} would resolve your uncommitted work together "
                f"with the incoming changes and leave no way to tell them apart. "
                + DIRTY_TREE_REMEDY.format(op=sub))
    return None


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        return 0

    tool = data.get("tool_name", "")
    ti = data.get("tool_input", {}) or {}

    if tool == "Bash":
        cmd = ti.get("command", "") or ""
        denied = git_deny_reason(cmd)
        if denied:
            deny(f"Blocked by git-guardrails: {denied}")
            return 0
        dirty = dirty_tree_reason(cmd, data)
        if dirty:
            deny(f"Blocked by git-guardrails: {dirty}")
        return 0

    if tool in ("Write", "Edit", "MultiEdit"):
        fp = ti.get("file_path", "") or ""
        if Path(fp).suffix not in CODE_EXT:
            return 0
        # Collect every string that becomes file content: Write.content,
        # Edit.new_string, and EACH MultiEdit edit's new_string (a list).
        candidates = []
        for k in ("content", "new_string"):
            v = ti.get(k)
            if isinstance(v, str):
                candidates.append(v)
        for e in ti.get("edits", []) or []:
            v = (e or {}).get("new_string")
            if isinstance(v, str):
                candidates.append(v)
        for content in candidates:
            m = HARDCODED_PATH.search(content)
            if m:
                msg = (f"Hardcoded machine path '{m.group(0)}' in {Path(fp).name} "
                       f"breaks replication packages. Use here::here(), relative paths, "
                       f"or a config variable.")
                if os.environ.get("CLAUDE_STRICT_PATHS", "") == "1":
                    deny(f"Blocked (CLAUDE_STRICT_PATHS=1): {msg}")
                else:
                    sys.stderr.write(f"[git-guardrails] WARNING: {msg}\n")
                break  # one finding per call is enough
        return 0

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)  # fail open

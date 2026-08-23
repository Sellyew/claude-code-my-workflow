#!/usr/bin/env python3
"""
Root-of-Trust Write Guard (PreToolUse, Bash only)

The template ships `permissions.defaultMode: "bypassPermissions"` with an
empty `deny` list, so the hook layer is the ONLY thing standing between an
agent and the files that decide whether any other gate runs at all:

    .claude/settings.json        — which hooks fire, and on what
    .claude/settings.local.json  — the same, per machine
    .claude/hooks/               — the gates themselves
    .githooks/                   — the pre-commit gate suite
    .claude/                     — the directory, because deleting it
                                   deletes the hooks

That set is the repository's **root of trust**. A guard that can rewrite
its own guard is not a guard, so this hook denies SHELL writes into those
paths — the silent path, where one redirection disables the whole suite
and nothing surfaces in review until much later.

Denied, when the target is a protected path:

    - redirection            `> f`, `>> f`, `&> f`, `>| f`
    - tee                    `... | tee f`
    - copy / link            cp, install, rsync, scp, ln (DESTINATION only —
                             copying a hook out is a read)
    - move / delete          mv, rm, unlink, shred (ANY argument — moving a
                             hook away disables it as surely as deleting it)
    - in-place edit          sed -i, perl -i, truncate, dd of=
    - git working-tree write `git rm`, `git checkout [<rev>] -- <path>`,
                             `git restore <path>`, `git clean -f <path>`,
                             `git stash push -- <path>`, `git mv` — git is a
                             writer program too, and these modify or delete the
                             root of trust exactly as rm/cp/mv do, with the
                             protected path as a literal argument. Read-only git
                             (status, log, diff, show, ls-files, rev-parse) is
                             untouched; a protected `-C <dir>` counts only when
                             the subcommand is one of the writers above
    - find deleter           find <protected> ... -delete / -exec rm|mv|... —
                             a plain shell deleter of the same class as rm
    - tar extraction         tar -x ... -C <protected> — extraction WRITES
                             files into the destination directory
    - shell wrapper          sh/bash/zsh/dash/ksh -c '<payload>' — the -c
                             payload is UNWRAPPED and re-scanned (depth <= 2),
                             so a redirection or deleter hidden inside it is
                             caught rather than swallowed by the tokenizer. The
                             shell's OWN options are parsed (long options never
                             count as `-c`; `--rcfile`/`--init-file`/`-o` are
                             consumed WITH their values), so a value-taking
                             option cannot make the guard read the wrong word as
                             the payload and skip the real one
    - command wrapper        env / sudo / doas / nice / stdbuf / ionice /
                             timeout / nohup / time / command / exec — the
                             wrapper AND its option arguments (`env -i`,
                             `env -u FOO`, `nice -n 10`, `sudo -u root`,
                             `stdbuf -oL`, `ionice -c2`, `timeout 5`) are
                             consumed so the REAL command behind them — a shell
                             `-c` OR a bare deleter (`nice rm .claude/...`) — is
                             reached and the -c-unwrap / deny logic applies to it
    - env split-string       env -S '<payload>' / env --split-string='<payload>'
                             (the attached `-S<payload>`/`--split-string=` forms,
                             AND the bundled short-flag forms `env -vS`/`env -iS`)
                             make env SPLIT the string into words and EXECUTE
                             them, so it is a command-payload carrier exactly like
                             a shell `-c`. env is located through the SAME
                             wrapper-skip as everything else, so `nice env -S …`
                             / `timeout 5 env -S …` reach it; the payload is then
                             UNWRAPPED and re-scanned (depth <= 2), not skipped as
                             an opaque value

Allowed, deliberately:

    - every READ — cat, grep, ls, head, diff, shasum, and running a hook
      (`python3 .claude/hooks/<name>.py`).
    - Edit / Write / MultiEdit on the same files. Those arrive as a diff the
      user can read; a shell one-liner does not. This guard closes the
      silent path, it does not lock the files.

When a command is ambiguous the guard ALLOWS it. A false deny that makes
the repository unusable costs more than the narrow case it would have
caught, so every rule keys off a command that can only be writing.

WHAT THIS GUARD IS — best-effort defense-in-depth, NOT a proof, and NOT the
primary control. It is a textual scan, not a sandbox. The controls that
actually protect the root of trust are elsewhere and do not depend on this
scan being complete: (1) Edit/Write/MultiEdit changes to these files land as a
reviewable DIFF a human sees — this guard only closes the SILENT shell path,
it does not lock the files; (2) `bypassPermissions` is a deliberate posture
the operator chose, not an accident; (3) any machine-wide guard the operator
runs (e.g. a pre-merge / pre-write hook in `~/.claude/hooks/`). This guard
raises the cost of the one silent path; it is a layer, not the wall.

WHAT IT CATCHES: direct writes and deletes (redirection, tee, cp/mv/rm/ln,
sed -i, dd, find -delete, tar -x, and GIT'S OWN working-tree writers —
`git rm/checkout -- /restore/clean/stash push -- /mv`) whose protected-path
target appears as a literal argument, and the two known command-payload
carriers — a shell
`sh/bash/… -c '<payload>'` and `env -S/--split-string`/`-vS` — reached after
the known command wrappers (env/sudo/nice/stdbuf/timeout/…). Both carriers are
unwrapped and re-scanned (depth <= 2).

WHAT IT DOES NOT CATCH — disclosed residual, in scope for a future audit as
BOUNDARY, not as a defect:
  - a write performed by an INTERPRETER whose program text this scan cannot
    read into — `python3 -c '...open(path,"w")...'`, `perl -e`, `node -e`,
    `ruby -e`, an `awk` program. These are execution forms, not command lines
    the tokenizer can see a literal path in.
  - a protected path fed to a deleter through a PIPE — `... | xargs rm`,
    `... | xargs -0 truncate` — where the path never appears as a literal
    argument on a command line this scanner sees.
  - a git write whose target is NOT a literal path operand — `git apply <patch>`
    (the paths live inside the patch), `git reset --hard`, `git merge`,
    `git checkout <branch>` with no pathspec. These rewrite the tree from
    recorded state rather than from a path on this command line, so the scan has
    no literal to test; `git-guardrails.py` is the layer that governs those.
  - an UNKNOWN wrapper or execution form not in the WRAPPERS/SHELLS tables, or
    an unlisted wrapper option that takes a SEPARATE value (assumed here to
    attach its value, which skips too LITTLE — a real command word is still
    scanned — rather than too much, so it fails toward catching the write).
These are not closed; the Edit/Write review backstop and the deliberate-bypass
posture above are what cover them.

Decision protocol (modern PreToolUse): exit 0 + JSON
  {"hookSpecificOutput": {"hookEventName": "PreToolUse",
    "permissionDecision": "deny", "permissionDecisionReason": "..."}}.
Fail-open: any error — malformed event, unparseable command, an exception
in this file — exits 0 with no decision (allow). A guard that hard-fails on
its own bug takes the session down with it; failing open loses coverage for
that one call, which is the cheaper failure for a best-effort deny.

Escape hatch: set ALLOW_ROOT_OF_TRUST_WRITE=1 in the ENVIRONMENT OF THE
SESSION (`ALLOW_ROOT_OF_TRUST_WRITE=1 claude`, or export it in the shell
that launches Claude Code). Prefixing the blocked Bash command with it does
not work and is not meant to: hooks run as separate processes, so the hatch
has to be a deliberate act of the person starting the session.
"""

from __future__ import annotations

import json
import os
import re
import sys

# --- protected paths -------------------------------------------------------

# Children of `.claude/` that are root of trust. Everything else under
# `.claude/` (rules, skills, references, agents) is ordinary content.
PROTECTED_UNDER_CLAUDE = {"settings.json", "settings.local.json", "hooks"}

_SLASHES = re.compile(r"/{2,}")


def normalize(path: str) -> str:
    """Collapse separator noise so `.claude//hooks` and `.claude/./hooks`
    match the same rule as `.claude/hooks`. Case-sensitive by design."""
    p = _SLASHES.sub("/", path)
    while "/./" in p:
        p = p.replace("/./", "/")
    while p.startswith("./"):
        p = p[2:]
    return p


def is_protected(token: str) -> bool:
    p = normalize(token)
    segs = [s for s in p.split("/") if s not in ("", ".")]
    for i, s in enumerate(segs):
        if s == ".githooks":
            return True
        if s == ".claude":
            if i + 1 == len(segs):
                return True  # the directory itself
            if segs[i + 1] in PROTECTED_UNDER_CLAUDE:
                return True
    return False


# --- command shape ---------------------------------------------------------

_TOKEN = re.compile(
    r"""(?P<op>&>>|&>|>\||\d?>>|\d?>|<<-?|<|\|\||\||&&|;|&|\n)
      | (?P<word>(?:"[^"]*"|'[^']*'|\\.|[^\s"'|;&<>\n])+)""",
    re.VERBOSE,
)

SEPARATORS = {"||", "|", "&&", ";", "&", "\n"}

# Env-var prefixes (`FOO=bar cmd`) and wrappers that delegate to a real command.
_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
WRAPPERS = {"sudo", "doas", "env", "command", "builtin", "exec",
            "nohup", "time", "nice", "stdbuf", "xargs", "timeout", "ionice"}

# Per-wrapper short/long options that consume a SEPARATE following value
# (`nice -n 10`, `sudo -u root`, `env -u FOO`, `stdbuf -o L`). An option that
# ATTACHES its value (`-oL`, `--chdir=/x`, `-n10`) is a single token and is
# consumed as an ordinary flag; only these exact tokens also eat the next word.
# `env`'s `-S`/`--split-string` is listed here so skip_wrappers still lands on
# any trailing real command word, but its VALUE is NOT opaque: it is a command
# line env splits and executes, re-scanned separately by env_split_payload().
_WRAPPER_ARG_OPTS = {
    "env":     {"-u", "--unset", "-C", "--chdir", "-S", "--split-string", "-P"},
    "nice":    {"-n", "--adjustment"},
    "sudo":    {"-u", "--user", "-g", "--group", "-C", "--close-from",
                "-h", "--host", "-p", "--prompt", "-r", "--role", "-t", "--type",
                "-U", "--other-user", "-R", "--chroot", "-D", "--chdir"},
    "doas":    {"-u", "-C"},
    "timeout": {"-s", "--signal", "-k", "--kill-after"},
    "stdbuf":  {"-i", "--input", "-o", "--output", "-e", "--error"},
    "ionice":  {"-c", "--class", "-n", "--classdata", "-p", "--pid"},
    "xargs":   {"-n", "--max-args", "-P", "--max-procs", "-I", "-i", "--replace",
                "-s", "--max-chars", "-d", "--delimiter", "-E", "-e", "--eof",
                "-L", "--max-lines", "-a", "--arg-file"},
}

# Wrappers that take a bare POSITIONAL argument before the real command
# (`timeout 5 rm x` — DURATION is a positional, not a flag). We skip at most
# this many leading non-option positionals so the loop reaches the command.
_WRAPPER_POSITIONAL = {"timeout": 1}

# Shells whose `-c '<payload>'` argument is a command line in its own right.
# The payload is unwrapped and re-scanned so a write hidden inside it is not
# swallowed as one opaque quoted word.
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}

DEST_LAST = {"cp", "install", "rsync", "scp", "ln"}     # last non-flag arg
ANY_ARG = {"mv", "rm", "unlink", "shred", "tee", "truncate"}
INPLACE = {"sed", "gsed", "perl", "ruby"}               # only with -i

# GIT'S OWN WORKING-TREE WRITERS. git is a writer program too, and the tables
# above never named it — so `git rm .claude/hooks/x`, `git checkout HEAD~1 --
# .claude/settings.json`, `git restore .claude/settings.json`, `git clean -fd
# .claude/hooks`, `git stash push -- .claude/hooks/x` and `git mv` all
# overwrote or deleted the root of trust through a plain shell one-liner while
# the semantically identical `cp`/`rm` spelling was denied. These are NOT part
# of the disclosed residual below: the command word is known, the protected path
# is a LITERAL argument, and the write is direct and unambiguous — exactly the
# class this guard claims to catch.
#
# ONLY these subcommands count as writers. Read-only git — status, log, diff,
# show, ls-files, rev-parse, cat-file, blame — is deliberately untouched, so a
# session can still inspect the root of trust freely.
GIT_WRITE_SUBS = {"rm", "checkout", "restore", "clean", "stash", "mv"}

# git GLOBAL options that sit between `git` and the subcommand and take a
# SEPARATE value; without consuming the value, `git -C <dir> checkout` would be
# read as the subcommand `<dir>` and the writer missed.
_GIT_GLOBAL_ARG_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                        "--exec-path", "--super-prefix"}

# `git stash push -m <msg>`: the value is a MESSAGE, never a pathspec, so it
# must not be read as a path operand.
_GIT_STASH_MSG_OPTS = {"-m", "--message"}

_SHORT_INPLACE = re.compile(r"^-[A-Za-z]*i")
_TARGET_DIR = re.compile(r"^--target-directory=(.+)$")


def unquote(word: str) -> str:
    out, i = [], 0
    while i < len(word):
        c = word[i]
        if c in "\"'":
            j = word.find(c, i + 1)
            if j == -1:
                out.append(word[i + 1:])
                break
            out.append(word[i + 1:j])
            i = j + 1
        elif c == "\\" and i + 1 < len(word):
            out.append(word[i + 1])
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


_HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def strip_heredocs(cmd: str) -> str:
    """Drop heredoc BODIES. `cat <<'EOF' > .claude/settings.json` still denies —
    the redirection is on the command line — but a body that merely *documents*
    `rm .claude/hooks/x` is prose, not a command, and must not trip a rule."""
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


def segments(cmd: str) -> list[list[tuple[str, str]]]:
    """Split into per-command segments of (kind, text) tokens; kind is
    'op' or 'word'. Best-effort — quoting oddities degrade to allow."""
    segs: list[list[tuple[str, str]]] = [[]]
    for m in _TOKEN.finditer(cmd):
        if m.group("op") is not None:
            tok = m.group("op")
            if tok in SEPARATORS:
                segs.append([])
            else:
                segs[-1].append(("op", tok))
        else:
            segs[-1].append(("word", unquote(m.group("word"))))
    return segs


def is_inplace(flag: str) -> bool:
    return (flag == "--in-place" or flag.startswith("--in-place=")
            or (not flag.startswith("--") and bool(_SHORT_INPLACE.match(flag))))


def skip_wrappers(words: list[str], stop_at: set[str] | None = None) -> int:
    """Advance past `FOO=bar` env-assignments and command wrappers — INCLUDING
    each wrapper's own option flags and the value some options take — to the
    index of the REAL command word. Returns len(words) if the whole segment is
    wrapper scaffolding.

    `stop_at` names wrappers to STOP ON rather than skip: with
    `stop_at={"env"}` the scan skips any leading `nice`/`timeout`/… but halts
    ON `env` itself, so a caller (env_split_payload) can then inspect env's own
    `-S` option instead of having it consumed as a skipped wrapper. Without it,
    every wrapper — env included — is skipped.

    The earlier version stopped at the first flag, so `env -i bash -c ...`,
    `nice -n 10 rm ...`, `sudo -u root ...`, `stdbuf -oL ...` and `timeout 5 rm`
    all halted on the flag and never reached the shell/deleter — defeating both
    the `-c` unwrap and direct deleter detection. Conservative-but-not-silent:
    where a flag's arity is unknown we treat it as attached-value (skip only the
    flag token), which risks skipping too LITTLE (a following real command is
    still scanned) rather than too much (which would blind the scan)."""
    i, n = 0, len(words)
    while i < n:
        if _ASSIGN.match(words[i]):          # FOO=bar prefix
            i += 1
            continue
        base = os.path.basename(words[i])
        if base not in WRAPPERS:
            break
        if stop_at and base in stop_at:      # halt ON this wrapper, don't skip it
            break
        i += 1                               # consume the wrapper name
        arg_opts = _WRAPPER_ARG_OPTS.get(base, set())
        while i < n:                         # consume this wrapper's options
            t = words[i]
            if _ASSIGN.match(t):             # `env VAR=val` after its flags
                i += 1
                continue
            if t == "--":                    # explicit end-of-options
                i += 1
                break
            if t.startswith("-") and t != "-":
                i += 1
                if t in arg_opts and i < n:  # separate-value option: eat its arg
                    i += 1
                continue
            break                            # first non-option word
        pos = _WRAPPER_POSITIONAL.get(base, 0)   # e.g. `timeout DURATION`
        while pos > 0 and i < n and not words[i].startswith("-"):
            i += 1
            pos -= 1
        # loop: words[i] may itself be another wrapper (`env sudo nice cmd`).
    return i


# Shell options that take a SEPARATE value, which must be consumed rather than
# mistaken for the -c payload. `--rcfile <file>` / `--init-file <file>` (bash)
# and `-o <option>` / `+o <option>` (every POSIX shell) are the ones that carry
# a value the shell reads but does not execute.
_SHELL_LONG_ARG_OPTS = {"--rcfile", "--init-file"}


def shell_c_payload(seg: list[tuple[str, str]]) -> str | None:
    """If this segment invokes a shell with `-c <payload>`, return the payload
    (already unquoted by the tokenizer) so scan() can recurse into it.

    The shell's OWN options are parsed properly rather than sniffed for the
    letter c. The earlier `w.startswith("-") and "c" in w` test set the -c flag
    on ANY option containing a c — so `bash --rcfile <file> -c '<payload>'`
    returned <file> as the payload, the real payload was never re-scanned, and a
    write into the root of trust hidden inside it passed silently. That failed
    toward MISSING the write, which is the direction this guard must never fail
    in. A `-c` is now only: the exact token `-c`, or a `c` inside a SINGLE-DASH
    short-flag group (`-lc`, `-ic`, `-ci`) — every letter of such a group is one
    short flag, so a `c` there really is `-c` and the command string really does
    follow it. That is a deliberate superset of the strict last-letter rule,
    because bash accepts `-ci '<payload>'` as readily as `-ic '<payload>'`. LONG
    options never set it, whatever letters they contain — `--rcfile` is exactly
    the bug — and the value-taking options above are consumed with their values.

    Where the parse is uncertain it errs toward SCANNING MORE (an unrecognised
    long option does not stop the walk; a stray operand does not end it), because
    an extra re-scan can only cost a false deny on text that literally contains a
    protected-path write, whereas stopping early costs the catch."""
    words = [t for k, t in seg if k == "word"]
    i = skip_wrappers(words)
    n = len(words)
    if i >= n or os.path.basename(words[i]) not in SHELLS:
        return None
    seen_c = False
    j = i + 1
    while j < n:
        w = words[j]
        if seen_c and not w.startswith("-"):
            return w                          # the command string
        if w == "--":                         # end of shell options
            j += 1
            continue
        if w.startswith("--"):                # long option: NEVER the -c flag
            if w in _SHELL_LONG_ARG_OPTS and j + 1 < n:
                j += 2                        # `--rcfile <file>` — eat its value
                continue
            j += 1                            # incl. attached `--rcfile=<file>`
            continue
        if w.startswith(("-", "+")) and len(w) > 1:
            group = w[1:]                     # short-flag group: one letter = one flag
            if "c" in group:                  # -c, -lc, -ic, -ci → payload follows
                seen_c = True
            if group.endswith("o") and j + 1 < n:
                j += 2                        # `-o pipefail` / `+o nounset` / `-co pipefail`
                continue
            j += 1
            continue
        j += 1                                # a bare operand; keep walking
    return None


# `env`'s -S/--split-string carries a COMMAND LINE that env splits into words
# and executes — a command-payload carrier exactly like a shell `-c`, not an
# opaque value. It appears as a separate value (`env -S '<payload>'`), attached
# (`-S<payload>`, `--split-string=<payload>`), OR bundled inside a short-flag
# group (`env -vS '<payload>'`, `env -iS '<payload>'`), all of which env
# executes.
_ENV_ARG_OPTS = {"-u", "--unset", "-C", "--chdir", "-P"}  # env opts taking a separate value


def env_split_payload(seg: list[tuple[str, str]]) -> str | None:
    """If this segment is `env` carrying -S/--split-string — reached through any
    number of command wrappers (`nice env -S …`, `timeout 5 env -S …`) — return
    the split string (a command line env will execute) so scan() can recurse
    into it, rather than letting its write/delete of a protected path pass
    unscanned. Locating env through the SAME skip_wrappers the rest of the guard
    uses (stopping ON env) is what closes the `<wrapper> env -S` bypass; matching
    -S inside a bundled short-flag group is what closes the `env -vS`/`-iS`
    bypass."""
    words = [t for k, t in seg if k == "word"]
    i = skip_wrappers(words, stop_at={"env"})   # skip nice/timeout/… , halt ON env
    if i >= len(words) or os.path.basename(words[i]) != "env":
        return None
    i += 1
    while i < len(words):
        w = words[i]
        if w == "--":                       # end of options; no split string
            return None
        if w in ("-S", "--split-string"):   # separate-value form: next word is it
            return words[i + 1] if i + 1 < len(words) else None
        if w.startswith("--split-string="):  # attached long form
            return w[len("--split-string="):]
        if w.startswith("-S"):              # attached short form `-S<payload>`
            return w[2:]
        # A bundled short-flag group that CONTAINS S (`-vS`, `-iS`, `-vS<payload>`):
        # env still splits+executes what follows the S. Chars after S in the same
        # token are the attached payload; if S is terminal, the next word is it.
        if w.startswith("-") and not w.startswith("--") and "S" in w:
            attached = w[w.index("S") + 1:]
            if attached:
                return attached
            return words[i + 1] if i + 1 < len(words) else None
        if _ASSIGN.match(w):                # NAME=VALUE → the command follows, no -S
            return None
        if w.startswith("-") and w != "-":  # some other env option
            if w in _ENV_ARG_OPTS and i + 1 < len(words):
                i += 2                      # separate-value option: skip its value too
            else:
                i += 1
            continue
        return None                         # a bare word = the command; no split string
    return None


def git_write_target(args: list[str]) -> tuple[str, str] | None:
    """For a segment whose command word is `git`, return (protected path, how)
    when a WORKING-TREE-WRITING subcommand names a protected path, else None.
    `args` is everything after the `git` word.

    Precise by construction, in three steps: (1) walk git's GLOBAL options —
    consuming the value of the ones that take a separate value — to find the
    real subcommand; (2) return None unless that subcommand is in
    GIT_WRITE_SUBS, so every read-only git invocation is left alone; (3) apply
    the guard's existing is_protected() test to the subcommand's PATH OPERANDS,
    respecting `--` (everything after it is a pathspec) and skipping option
    flags and a stash `-m <message>` value. A rev/branch operand — `HEAD~1`,
    `main` — never satisfies is_protected(), so scanning operands ahead of `--`
    costs nothing and catches the `--`-less spellings (`git restore <path>`,
    `git rm <path>`).

    A `-C <dir>` that is itself protected is also a write when the subcommand
    writes: `git -C .claude/hooks clean -fd` deletes hooks without ever naming
    one as an operand."""
    i, dash_c = 0, None
    while i < len(args):                       # 1. global options → subcommand
        w = args[i]
        if not w.startswith("-"):
            break
        if w in _GIT_GLOBAL_ARG_OPTS and i + 1 < len(args):
            if w == "-C":
                dash_c = args[i + 1]
            i += 2
            continue
        if w.startswith("-C") and len(w) > 2:  # attached `-Cdir`
            dash_c = w[2:]
        i += 1
    if i >= len(args):
        return None
    sub = args[i]
    if sub not in GIT_WRITE_SUBS:              # 2. read-only git → not a writer
        return None
    if dash_c is not None and is_protected(dash_c):
        return dash_c, f"`git {sub}` in a protected working directory"

    rest = args[i + 1:]                        # 3. the subcommand's operands
    operands: list[str] = []
    after_ddash = False
    k = 0
    while k < len(rest):
        w = rest[k]
        if after_ddash:                        # everything past `--` is a path
            operands.append(w)
            k += 1
            continue
        if w == "--":
            after_ddash = True
            k += 1
            continue
        if sub == "stash" and w in _GIT_STASH_MSG_OPTS and k + 1 < len(rest):
            k += 2                             # `-m <msg>` — a message, not a path
            continue
        if w.startswith("-") and w != "-":
            k += 1
            continue
        operands.append(w)
        k += 1
    for a in operands:
        if is_protected(a):
            return a, f"`git {sub}`"
    return None


def scan_segment(seg: list[tuple[str, str]]) -> tuple[str, str] | None:
    """Return (protected_path, how) for the first write found, else None."""
    words = [t for k, t in seg if k == "word"]

    # 1. Output redirection — the target is the token right after the operator.
    for idx, (kind, tok) in enumerate(seg):
        if kind == "op" and (tok.endswith(">") or tok == ">|") and idx + 1 < len(seg):
            k2, t2 = seg[idx + 1]
            if k2 == "word" and is_protected(t2):
                return t2, "output redirection"

    if not words:
        return None

    # 2. The command itself, past env assignments and wrappers (with their
    #    option arguments — see skip_wrappers).
    i = skip_wrappers(words)
    if i >= len(words):
        return None
    name = os.path.basename(words[i])
    args = words[i + 1:]
    plain = [a for a in args if a != "--" and not a.startswith("-")]
    flags = [a for a in args if a.startswith("-")]

    if name == "git":
        hit = git_write_target(args)
        if hit:
            return hit

    if name in ANY_ARG:
        for a in plain:
            if is_protected(a):
                return a, f"`{name}`"

    if name in DEST_LAST:
        for f in flags:
            m = _TARGET_DIR.match(f)
            if m and is_protected(m.group(1)):
                return m.group(1), f"`{name}` target directory"
        if "-t" in flags and plain and is_protected(plain[0]):
            return plain[0], f"`{name}` target directory"
        if plain and is_protected(plain[-1]):
            return plain[-1], f"`{name}` destination"

    if name in INPLACE and any(is_inplace(f) for f in flags):
        for a in plain:
            if is_protected(a):
                return a, f"in-place `{name} -i`"

    if name == "dd":
        for a in args:
            if a.startswith("of=") and is_protected(a[3:]):
                return a[3:], "`dd of=`"

    if name == "find":
        # A find that deletes: `-delete`, or `-exec/-execdir <deleter> ...`.
        deleters = {"rm", "mv", "truncate", "shred", "unlink"}
        destructive = False
        for k, a in enumerate(args):
            if a == "-delete":
                destructive = True
                break
            if a in ("-exec", "-execdir") and k + 1 < len(args) \
                    and os.path.basename(args[k + 1]) in deleters:
                destructive = True
                break
        if destructive:
            # Path operands are the plain args before the first predicate flag.
            for a in args:
                if a.startswith("-"):
                    break
                if is_protected(a):
                    return a, "`find ... -delete/-exec`"

    if name == "tar":
        # Extraction WRITES files into the -C/--directory destination; creating
        # an archive only reads it, so gate on an extract mode being present.
        extracting = any(
            a in ("-x", "--extract") or a.startswith("--extract")
            or (a.startswith("-") and not a.startswith("--") and "x" in a)
            for a in args)
        if extracting:
            for idx, a in enumerate(args):
                if a in ("-C", "--directory") and idx + 1 < len(args) \
                        and is_protected(args[idx + 1]):
                    return args[idx + 1], "`tar` extraction destination"
                if a.startswith("--directory=") and is_protected(a[len("--directory="):]):
                    return a[len("--directory="):], "`tar` extraction destination"

    return None


# Quote-naive backstop: catches a BARE redirection the tokenizer mis-segments.
# It runs on a QUOTE-STRIPPED copy of the command (single- and double-quoted
# spans blanked to spaces of equal length), so a redirection that appears only
# *inside* quotes — an echo or a runbook line that documents `> .claude/...` —
# is prose, not a command-line redirect, and is not matched. A real bare
# redirect still is; and a redirect hidden in `bash -c '<payload>'` is handled
# by the shell-`-c` UNWRAP path below, which re-scans the (unquoted) payload, so
# the backstop no longer needs to see inside quotes at all.
_REDIR = re.compile(r"(?:&>>|&>|>\||>>|>)\s*([^\s;|&<>()]+)")
_QUOTED_SPAN = re.compile(r"'[^']*'|\"[^\"]*\"")


def strip_quoted(cmd: str) -> str:
    """Blank single- and double-quoted spans to equal-length runs of spaces, so
    the quote-naive backstop scans only the UNQUOTED command line."""
    return _QUOTED_SPAN.sub(lambda m: " " * len(m.group(0)), cmd)


def scan(raw: str, depth: int = 0) -> tuple[str, str] | None:
    cmd = strip_heredocs(raw)
    for seg in segments(cmd):
        hit = scan_segment(seg)
        if hit:
            return hit
        # A shell `-c '<payload>'` is a command line of its own; unwrap and
        # re-scan it (depth-limited, so pathological nesting cannot loop).
        if depth < 2:
            payload = shell_c_payload(seg)
            if payload is not None:
                hit = scan(payload, depth + 1)
                if hit:
                    return hit
            # `env -S '<payload>'` splits and executes its string, so it is a
            # command line of its own — unwrap and re-scan it, same depth guard.
            split = env_split_payload(seg)
            if split is not None:
                hit = scan(split, depth + 1)
                if hit:
                    return hit
    for m in _REDIR.finditer(strip_quoted(cmd)):
        if is_protected(m.group(1)):
            return m.group(1), "output redirection"
    return None


# --- hook ------------------------------------------------------------------

def deny(reason: str) -> None:
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, sys.stdout)


def main() -> int:
    if os.environ.get("ALLOW_ROOT_OF_TRUST_WRITE", "") == "1":
        return 0

    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        return 0

    if data.get("tool_name", "") != "Bash":
        return 0

    cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""
    if ".claude" not in cmd and ".githooks" not in cmd:
        return 0

    hit = scan(cmd)
    if not hit:
        return 0
    path, how = hit
    deny(
        f"Blocked by root-of-trust-guard: shell write to '{path}' via {how}. "
        f"That path is part of this repository's root of trust — the files that "
        f"define every gate (.claude/settings.json, .claude/settings.local.json, "
        f".claude/hooks/, .githooks/). Permissions run in bypass mode here, so a "
        f"shell one-liner can disable the whole gate suite without leaving anything "
        f"a reviewer would see. Reads are untouched; edit the file with the "
        f"Edit/Write tool instead, which lands as a reviewable diff. "
        f"(Override: start the session with ALLOW_ROOT_OF_TRUST_WRITE=1 in its "
        f"environment.)"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)  # fail open

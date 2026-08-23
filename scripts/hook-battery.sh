#!/usr/bin/env bash
# hook-battery.sh — prove the ACTIVE guard hooks still fire.
#
# A hook is the one gate nobody watches. It runs in a subprocess, its output is
# a decision the harness consumes, and when it stops working it stops working
# SILENTLY: no error, no red gate, just a session that behaves as though the
# hook had nothing to say. `check-ledger-coverage.py` proves each hook is WIRED
# to a file that exists. This battery proves the file still DOES something —
# it re-seeds each guard's target failure on every run and checks that the
# guard goes red on it, and stays quiet on a clean control.
#
# Covered (the three guards that make a DECISION; the passive convenience hooks
# are listed as visible debt in quality_reports/qualification/LEDGER.md):
#
#   root-of-trust-guard.py   shell write into the repo's root of trust
#   git-guardrails.py        destructive git + the clean-tree precondition
#   claim-reconcile.py       numeric claims that a just-edited file can stale
#
# Every fixture is built under a mktemp directory that is removed on exit; the
# real .claude/ tree is never written to, and the throwaway git repository is
# created inside the temp directory, never the repo under test.
#
# HOOK_DIR overrides which hook directory is exercised. That is how the battery
# itself is qualified: point it at a stub guard that always allows and it must
# go red, because a battery that cannot fail is decoration.
#
# Exit 0 = every case passed. Exit 1 = at least one case failed (named on
# stdout). Exit 2 = the battery could not run, which is a failure, not a pass.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if [ -z "${DIR:-}" ] || [ ! -d "$DIR" ]; then
    echo "hook-battery: cannot resolve script directory" >&2; exit 2
fi
ROOT="$(cd "$DIR/.." && pwd)"
HOOKS="${HOOK_DIR:-$ROOT/.claude/hooks}"

for h in root-of-trust-guard.py git-guardrails.py claim-reconcile.py; do
    if [ ! -f "$HOOKS/$h" ]; then
        echo "hook-battery: CANNOT RUN — $HOOKS/$h does not exist" >&2
        echo "  A battery that could not run is not a passing battery." >&2
        exit 2
    fi
done
if ! command -v git >/dev/null 2>&1; then
    echo "hook-battery: CANNOT RUN — git is not on PATH (cases c1-c3 need a throwaway repo)" >&2
    exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "hook-battery: CANNOT RUN — python3 is not on PATH (every case invokes it)" >&2
    echo "  A battery that could not run is not a passing battery." >&2
    exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/hook-battery.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM

PASS=0; FAIL=0; FAILED=()
ok() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); FAILED+=("$1"); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

OUT=""; RC=0
fire() {  # fire <hook-file> <event-json> [VAR=VAL ...]  -> sets OUT, RC
    local hook="$1" ev="$2"; shift 2
    OUT="$(env -u ALLOW_ROOT_OF_TRUST_WRITE -u ALLOW_DIRTY_MERGE -u CLAUDE_STRICT_PATHS \
           "$@" python3 "$HOOKS/$hook" < "$ev" 2>/dev/null)"
    RC=$?
}
fire_in() {  # fire_in <hook-process-cwd> <hook-file> <event-json> -> sets OUT, RC
    # The hook PROCESS's working directory is not the event's `cwd`: hooks are
    # spawned by the CLI process while the Bash tool's directory drifts. Case
    # c25 needs the two to DIFFER, so it runs the guard from somewhere else.
    local dir="$1" hook="$2" ev="$3"
    OUT="$(cd "$dir" && env -u ALLOW_ROOT_OF_TRUST_WRITE -u ALLOW_DIRTY_MERGE \
           -u CLAUDE_STRICT_PATHS python3 "$HOOKS/$hook" < "$ev" 2>/dev/null)"
    RC=$?
}

expect_deny() {     # the guard must refuse
    if [ "$RC" -ne 0 ]; then no "$1" "hook exited $RC (a PreToolUse guard must exit 0)"; return; fi
    case "$OUT" in
        *'"permissionDecision": "deny"'*) ok "$1" ;;
        *) no "$1" "no deny decision emitted — stdout was: ${OUT:-<empty>}" ;;
    esac
}
expect_silent() {   # the clean control: allowed, and nothing said
    if [ "$RC" -ne 0 ]; then no "$1" "hook exited $RC (expected 0 — hooks fail open)"; return; fi
    if [ -n "$OUT" ]; then no "$1" "expected silence, got: $OUT"; else ok "$1"; fi
}
expect_contains() { # expect_contains <name> <substring>
    if [ "$RC" -ne 0 ]; then no "$1" "hook exited $RC (expected 0)"; return; fi
    case "$OUT" in
        *"$2"*) ok "$1" ;;
        *) no "$1" "expected substring '$2' — stdout was: ${OUT:-<empty>}" ;;
    esac
}

echo "hook-battery: do the active guard hooks still fire?"
echo "  hooks under test: $HOOKS"

# ── (a) root-of-trust-guard ────────────────────────────────────────────────
# The guard's whole job is the SILENT path: a shell one-liner that rewrites the
# files deciding whether any other gate runs. Seed one; then three controls.
echo ""
echo "  (a) root-of-trust-guard.py"

cat > "$TMP/a1.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"printf disabled | tee .claude//settings.json"}}
EOF
cat > "$TMP/a2.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"cat .claude/settings.json | head -20"}}
EOF
printf '%s\n' 'this is not json at all {' > "$TMP/a3.json"

fire root-of-trust-guard.py "$TMP/a1.json"
expect_deny   "a1 shell write into the root of trust is denied"
fire root-of-trust-guard.py "$TMP/a2.json"
expect_silent "a2 clean control: reading the same file is allowed"
fire root-of-trust-guard.py "$TMP/a3.json"
expect_silent "a3 malformed event fails OPEN (exit 0, no decision)"
fire root-of-trust-guard.py "$TMP/a1.json" ALLOW_ROOT_OF_TRUST_WRITE=1
expect_silent "a4 documented escape hatch actually disarms the guard"

# a5/a6: a redirection wrapped in `bash -c '...'` (the -c payload is unwrapped
# and re-scanned) and a `find ... -delete` of a hook dir — both were bypasses
# before this fix, so they are pinned as regression cases here.
cat > "$TMP/a5.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"bash -c 'printf disabled > .claude/settings.json'"}}
EOF
cat > "$TMP/a6.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"find .claude/hooks -name '*.py' -delete"}}
EOF
fire root-of-trust-guard.py "$TMP/a5.json"
expect_deny   "a5 redirection wrapped in bash -c is unwrapped and denied"
fire root-of-trust-guard.py "$TMP/a6.json"
expect_deny   "a6 find -delete of a hook directory is denied"

# a7: a pure echo that merely DOCUMENTS a redirection into a protected path,
# inside a quoted string, writes nothing and must be ALLOWED. The backstop scans
# a quote-stripped copy, so the redirect-mention inside quotes is prose, not a
# command-line redirect. (Regression: the round-1 fix over-matched this.)
cat > "$TMP/a7.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"echo \"to reset a wedged hook: printf '{}' > .claude/settings.json\""}}
EOF
fire root-of-trust-guard.py "$TMP/a7.json"
expect_silent "a7 quoted echo documenting a protected redirection is allowed"

# a8: a command WRAPPER carrying its own option flag (`env -i`, `nice -n N`,
# `sudo -u X`) must be skipped ALONG WITH its options so the real shell/deleter
# behind it is reached. Before this fix the loop halted on the first flag, so
# `env -i bash -c '<redirect>'` and `nice rm <protected>` both bypassed the
# guard entirely. Pinned as a regression case so the gap cannot silently regrow.
cat > "$TMP/a8.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"env -i bash -c 'printf disabled > .claude/settings.json'"}}
EOF
cat > "$TMP/a9.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"nice rm .claude/hooks/git-guardrails.py"}}
EOF
fire root-of-trust-guard.py "$TMP/a8.json"
expect_deny   "a8 flag-carrying wrapper (env -i bash -c) is unwrapped past its flags and denied"
fire root-of-trust-guard.py "$TMP/a9.json"
expect_deny   "a9 bare wrapper deleter (nice rm) reaches the real command and is denied"

# a10: `env -S '<payload>'` / `env --split-string='<payload>'` makes env SPLIT
# the string into words and EXECUTE them — a command-payload carrier exactly
# like a shell `-c`, not an opaque value. Before this fix -S sat in env's
# arg-opts and its value was skipped whole, letting a redirect/deleter of a
# protected path through. Pinned so the split-string bypass cannot regrow.
cat > "$TMP/a10.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"env -S 'printf disabled > .claude/settings.json'"}}
EOF
fire root-of-trust-guard.py "$TMP/a10.json"
expect_deny   "a10 env -S split-string carrying a redirect is unwrapped and denied"

# a11/a12: env -S reached THROUGH a command wrapper (`nice env -S …`) and the
# bundled short-flag form (`env -vS …`). Before this fix env_split_payload located
# `env` with its own assignment-only scanner, so a wrapper in front of env hid it
# and the `^-S`-anchored match missed a bundled `-vS` — both silently ALLOWED a
# protected-path write inside the split string. env is now located through the
# same skip_wrappers the rest of the guard uses, and any short-flag group ending
# in S is treated as the split-string carrier. Pinned so neither bypass regrows.
cat > "$TMP/a11.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"nice -n 10 env -S 'printf disabled > .claude/settings.json' true"}}
EOF
cat > "$TMP/a12.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"env -vS 'printf disabled > .claude/settings.json' true"}}
EOF
fire root-of-trust-guard.py "$TMP/a11.json"
expect_deny   "a11 wrapper-chained env -S (nice env -S <redirect>) is located past the wrapper and denied"
fire root-of-trust-guard.py "$TMP/a12.json"
expect_deny   "a12 bundled short-flag env -vS <redirect> is recognized as a split-string carrier and denied"

# a13/a14: the shell's OWN options. shell_c_payload used to spot `-c` with the
# loose test `w.startswith("-") and "c" in w`, so a VALUE-TAKING long option that
# merely contains the letter c — `bash --rcfile <file> -c '<payload>'` — set the
# -c flag on `--rcfile` and returned <file> as the payload; the real payload was
# never re-scanned and its deleter passed SILENTLY. That failed toward MISSING
# the write, the one direction this guard must never fail in. Options are now
# parsed: long options never count as -c, `--rcfile`/`--init-file`/`-o` are
# consumed WITH their values, and only a `c` inside a single-dash short group is
# the real flag. a14 pins the bundled form, which must keep working.
cat > "$TMP/a13.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"bash --rcfile /tmp/x -c 'rm .claude/hooks/git-guardrails.py'"}}
EOF
cat > "$TMP/a14.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"bash -ic 'rm .claude/hooks/git-guardrails.py'"}}
EOF
fire root-of-trust-guard.py "$TMP/a13.json"
expect_deny   "a13 value-taking shell option (bash --rcfile <f> -c <deleter>) no longer hides the real -c payload"
fire root-of-trust-guard.py "$TMP/a14.json"
expect_deny   "a14 bundled short-flag shell (bash -ic <deleter>) is still recognised as a -c carrier"

# a15: the control for that parser. Consuming `--rcfile`'s value must not start
# DENYING the ordinary case — a shell option parser that over-matches would make
# every `bash --rcfile <f> -c '<harmless>'` unusable, which is the failure mode
# the guard's own "when a command is ambiguous, ALLOW it" rule forbids.
cat > "$TMP/a15.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"bash --rcfile /tmp/x -c 'ls -la'"}}
EOF
fire root-of-trust-guard.py "$TMP/a15.json"
expect_silent "a15 clean control: the same shell options carrying a HARMLESS payload stay allowed"

# a16-a22: GIT'S OWN working-tree writers. The writer tables named cp/mv/rm/ln/
# sed -i/dd/find/tar but never git, so `git checkout HEAD~1 -- .claude/settings.json`
# restored the root of trust from an arbitrary revision — wiping every hook
# registration — through a plain shell one-liner with the protected path sitting
# there as a literal argument, while the semantically identical `cp`/`rm`
# spelling was DENIED. That is not the disclosed residual (interpreters,
# pipe-fed deleters, unknown wrappers): the command is known, the path literal,
# the write direct. Each writer is pinned here, including the `-C <protected>`
# form where the subcommand writes INSIDE the protected directory without ever
# naming a file in it.
cat > "$TMP/a16.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git checkout HEAD~1 -- .claude/settings.json"}}
EOF
cat > "$TMP/a17.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git restore .claude/hooks/git-guardrails.py"}}
EOF
cat > "$TMP/a18.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git rm .claude/hooks/git-guardrails.py"}}
EOF
cat > "$TMP/a19.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git clean -fd .claude/hooks"}}
EOF
cat > "$TMP/a20.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git stash push -m wip -- .claude/hooks/git-guardrails.py"}}
EOF
cat > "$TMP/a21.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git mv .claude/hooks/git-guardrails.py /tmp/parked.py"}}
EOF
cat > "$TMP/a22.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git -C .claude/hooks clean -fd"}}
EOF
fire root-of-trust-guard.py "$TMP/a16.json"
expect_deny   "a16 git checkout <rev> -- <protected> is a working-tree write and is denied"
fire root-of-trust-guard.py "$TMP/a17.json"
expect_deny   "a17 git restore <protected> is a working-tree write and is denied"
fire root-of-trust-guard.py "$TMP/a18.json"
expect_deny   "a18 git rm <protected> is denied (git deletes as surely as rm)"
fire root-of-trust-guard.py "$TMP/a19.json"
expect_deny   "a19 git clean -fd <protected dir> is denied (it deletes the hooks)"
fire root-of-trust-guard.py "$TMP/a20.json"
expect_deny   "a20 git stash push -- <protected> is denied (stashing a hook away disables it); the -m message value is not misread as a path"
fire root-of-trust-guard.py "$TMP/a21.json"
expect_deny   "a21 git mv <protected> <elsewhere> is denied (moving a hook away disables it)"
fire root-of-trust-guard.py "$TMP/a22.json"
expect_deny   "a22 git -C <protected dir> clean -fd is denied (the writer's working directory IS the protected path)"

# a23/a24: the controls for that table. Adding git as a writer must NOT start
# denying READ-ONLY git against the same paths — inspecting the root of trust is
# explicitly allowed ("every READ"), and a guard that blocks `git log` on its own
# hooks would violate the "when a command is ambiguous, ALLOW it" rule the same
# way an over-matching parser would.
cat > "$TMP/a23.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git log --oneline -- .claude/settings.json"}}
EOF
cat > "$TMP/a24.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git status --porcelain .claude/hooks"}}
EOF
fire root-of-trust-guard.py "$TMP/a23.json"
expect_silent "a23 clean control: read-only git (git log -- <protected>) stays allowed"
fire root-of-trust-guard.py "$TMP/a24.json"
expect_silent "a24 clean control: read-only git (git status <protected>) stays allowed"

# ── (b) git-guardrails: the deny list ──────────────────────────────────────
echo ""
echo "  (b) git-guardrails.py — destructive git"

cat > "$TMP/b1.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~1"}}
EOF
cat > "$TMP/b2.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease origin main"}}
EOF

fire git-guardrails.py "$TMP/b1.json"
expect_deny   "b1 git reset --hard is denied"
fire git-guardrails.py "$TMP/b2.json"
expect_silent "b2 clean control: --force-with-lease is allowed"

# b3/b4 (r9): git's GLOBAL options were ENUMERATED — seven of them — in the
# prefix every deny regex carries. git documents many more, so ONE innocuous
# unlisted option defeated the ENTIRE deny list: with `-P` (git's own short
# spelling of `--no-pager`, whose LONG spelling WAS listed) or
# `--no-optional-locks` inserted, reset --hard / clean -fd / push --force /
# add -A / checkout -- . all went SILENT. The table now enumerates only the
# options that take a SEPARATE VALUE and consumes any other dash-word as a
# one-token global, so an unknown option fails toward FINDING the subcommand.
cat > "$TMP/b3.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git -P reset --hard HEAD~1"}}
EOF
cat > "$TMP/b4.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git --no-optional-locks clean -fd"}}
EOF
fire git-guardrails.py "$TMP/b3.json"
expect_deny   "b3 r9: an UNENUMERATED git global option (git -P reset --hard) no longer bypasses the deny list"
fire git-guardrails.py "$TMP/b4.json"
expect_deny   "b4 r9: the same for a long unenumerated global (git --no-optional-locks clean -fd)"

# b5-b14 (r10): SHELL QUOTING defeated the whole deny list. The rules were
# regexes over the RAW command string while the clean-tree check next door had
# already been rebuilt to tokenise, so quoting ONE token made a destructive op
# invisible — executed against the shipped guard: `git reset --hard HEAD~1`
# DENIED, `git reset "--hard" HEAD~1` SILENT; `git add -A` DENIED, `git add
# '-A'` SILENT. The deny list now runs over the same unquoted TOKENS as the
# clean-tree check. One quoted spelling per GIT_DENY verb is pinned here —
# reset, clean, push, add, checkout, restore — plus the quoted SUBCOMMAND form,
# because quoting `git 'reset'` broke it just as thoroughly as quoting the flag.
cat > "$TMP/b5.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git reset \"--hard\" HEAD~1"}}
EOF
cat > "$TMP/b6.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git 'reset' --hard HEAD~1"}}
EOF
cat > "$TMP/b7.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git clean \"-fd\""}}
EOF
cat > "$TMP/b8.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git push \"--force\" origin main"}}
EOF
cat > "$TMP/b9.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git add '-A'"}}
EOF
cat > "$TMP/b10.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git add \"--all\""}}
EOF
cat > "$TMP/b11.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git checkout -- '.'"}}
EOF
cat > "$TMP/b12.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git restore \".\""}}
EOF
# b13/b14: the two controls for the port, one per direction.
#   b13 — a FULLY QUOTED mention writes nothing and must be SILENT. The old raw
#         regex DENIED this string; the tokenizer sees one word whose basename
#         is not `git`, so no invocation is found. (The UNQUOTED mention still
#         denies — the documented over-deny the clean-tree check already pays.)
#   b14 — quoting the SAFE flag must not start denying it either: the port must
#         not have bought its recall by matching substrings again.
cat > "$TMP/b13.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"echo \"never run git reset --hard here\""}}
EOF
cat > "$TMP/b14.json" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"git push \"--force-with-lease\" origin main"}}
EOF
fire git-guardrails.py "$TMP/b5.json"
expect_deny   "b5 r10: a QUOTED flag no longer evades the deny list (git reset \"--hard\" HEAD~1)"
fire git-guardrails.py "$TMP/b6.json"
expect_deny   "b6 r10: a QUOTED subcommand no longer evades it either (git 'reset' --hard HEAD~1)"
fire git-guardrails.py "$TMP/b7.json"
expect_deny   "b7 r10: quoted destructive clean (git clean \"-fd\") is denied"
fire git-guardrails.py "$TMP/b8.json"
expect_deny   "b8 r10: quoted force push (git push \"--force\" origin main) is denied"
fire git-guardrails.py "$TMP/b9.json"
expect_deny   "b9 r10: quoted blanket staging (git add '-A') is denied"
fire git-guardrails.py "$TMP/b10.json"
expect_deny   "b10 r10: the long quoted spelling (git add \"--all\") is denied"
fire git-guardrails.py "$TMP/b11.json"
expect_deny   "b11 r10: quoted mass discard (git checkout -- '.') is denied"
fire git-guardrails.py "$TMP/b12.json"
expect_deny   "b12 r10: the restore spelling of the same (git restore \".\") is denied"
fire git-guardrails.py "$TMP/b13.json"
expect_silent "b13 r10 control: a FULLY QUOTED mention writes nothing and is silent (the raw regex used to deny this string)"
fire git-guardrails.py "$TMP/b14.json"
expect_silent "b14 r10 control: quoting the SAFE flag keeps it allowed (git push \"--force-with-lease\") — the port did not buy recall with substring matching"

# ── (c) git-guardrails: the clean-tree precondition ────────────────────────
# Needs a real repository to answer `git status --porcelain`, so build a
# throwaway one inside the temp directory. Dirty first, then clean.
echo ""
echo "  (c) git-guardrails.py — merge must start from a clean tree"

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q >/dev/null 2>&1
: > "$REPO/untracked.txt"          # one untracked file == a dirty tree

# A SECOND, CLEAN checkout — the fixture case c17 needs. A `git -C <other> stash`
# must not vouch for the tree the merge actually runs in (a common worktree /
# second-clone setup), so the clean mark has to be keyed per repository.
OTHER_REPO="$TMP/other-repo"
mkdir -p "$OTHER_REPO"
git -C "$OTHER_REPO" init -q >/dev/null 2>&1   # no files == a clean tree

# ── r8: the rule this block now pins ───────────────────────────────────────
# The clean-tree check STOPPED SIMULATING THE SHELL. It is a closed
# whole-command allowlist: (1) no history op → silent; (2) an escape or
# self-managing op (`--abort`/`--continue`/`--skip`/`--quit`/`--edit-todo`/
# `--autostash`) → ALLOW without reading the tree; (3) otherwise read
# `git status --porcelain` LIVE in the directory the invocation itself names
# and DENY if it is non-empty — regardless of what any other segment claims.
#
# DELETED IN r8, because each of these tested ONLY the simulator that is gone:
#   old c7  `git stash push && git pull` ALLOW   — the stash-effect "clean" verdict
#   old c8  push && pop && merge DENY            — the redirty state machine
#   old c9  `-m pop` message-not-subcommand ALLOW— the stash subcommand parser
#   old c10 pathspec-limited push DENY           — the "partial" classification
#   old c11 `--keep-index` DENY                  — the stash FLAG allowlist
#   old c12 bare `-p` DENY                       — the stash FLAG allowlist
#   old c13 invented stash flag DENY             — the stash FLAG allowlist
#   old c14 `stash branch` DENY                  — the stash SUBCOMMAND allowlist
#   old c15 invented stash subcommand DENY       — the stash SUBCOMMAND allowlist
#   old c20 `git log > f` between DENY           — the inert-segment allowlist
#   old c21 `echo >> f` between DENY             — the inert-segment allowlist
#   old c22 inert `echo` preserves the mark ALLOW— the inert-segment allowlist
# Every one of them now resolves to the same trivial answer ("the tree is dirty,
# so DENY") and none of them can distinguish a working guard from a broken one.
# Old c4/c7/c9/c22 flipped ALLOW→DENY: that flip is the ACCEPTED COST, and c4
# below pins it so nobody "fixes" it back.
# Retained from earlier rounds: old c1→c1, c2→c2, c3→c3, c4→c4 (flipped),
# c5→c5, c6→c6, c16→c7, c17→c8, c18→c9, c19→c10.
cat > "$TMP/c1.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git merge feature-x"},"cwd":"$REPO"}
EOF
cat > "$TMP/c2.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git merge --abort"},"cwd":"$REPO"}
EOF
# c4: THE ACCEPTED COST, pinned. `git stash push -m x && git merge` used to be
# ALLOWED (the remedy the old deny message recommended). It is now DENIED,
# deliberately: the guard reads the tree, it does not simulate what the first
# half of a chain would have done to it. Eight rounds of trying to simulate that
# leaked eight times — including `git stash` not stashing UNTRACKED files at
# all, so this very chain could leave the tree dirty and still be allowed. The
# cost is one extra keystroke (run the two commands separately, which the guard
# re-checks) against an unbounded soundness hole. DO NOT "fix" this back.
cat > "$TMP/c4.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git stash push -m wip && git merge feature-x"},"cwd":"$REPO"}
EOF
# c5: a quoted -C path must not let a dirty merge through (the path is honoured,
# not stripped as a quoted span).
cat > "$TMP/c5.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git -C \"$REPO\" merge feature-x"}}
EOF
# c6: a `git commit` earlier in the chain licenses nothing either.
cat > "$TMP/c6.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git commit -m wip && git merge feature-x"},"cwd":"$REPO"}
EOF
# c7/c8/c10 (old c16/c17/c19): the historic bypass SHAPES, kept because they are
# the real command lines that leaked in rounds 6 and 7 — a dirtying command
# between the stash and the merge, a stash in a DIFFERENT checkout, and a
# redirection inside an "inert" echo. Under the new rule they deny for one
# reason, not three: the tree is dirty at decision time.
cat > "$TMP/c7.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git stash push -m wip && touch new.R && git merge feature-x"},"cwd":"$REPO"}
EOF
cat > "$TMP/c8.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git -C $OTHER_REPO stash && git merge feature-x"},"cwd":"$REPO"}
EOF
cat > "$TMP/c9.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git merge --autostash feature-x"},"cwd":"$REPO"}
EOF
cat > "$TMP/c10.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git stash push -m wip && echo note > b.txt && git merge feature-x"},"cwd":"$REPO"}
EOF
# c11-c13: the three r8 findings that broke the simulator, pinned against the
# rule that makes them harmless.
#   c11 — `cd <other repo> && git merge`. Repository identity is read from -C or
#         the event cwd only, so this is judged against the SESSION's repo,
#         which is dirty → DENY. (`cd` is disclosed as unseen in the docstring;
#         what matters is that it cannot make a dirty tree look clean.)
#   c12 — `echo $(touch f)`: a command substitution inside an allowlisted "inert"
#         command word. It used to preserve the clean mark and false-ALLOW.
#   c13 — the backtick spelling of the same thing.
cat > "$TMP/c11.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"cd $OTHER_REPO && git merge feature-x"},"cwd":"$REPO"}
EOF
cat > "$TMP/c12.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git stash push -m wip && echo \$(touch new1.R) && git merge feature-x"},"cwd":"$REPO"}
EOF
cat > "$TMP/c13.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git stash push -m wip && echo \`touch new2.R\` && git merge feature-x"},"cwd":"$REPO"}
EOF
# c14-c17: the rest of the closed allowlist.
#   c14 — rule 2 on a DIFFERENT op and a DIFFERENT escape flag (`rebase --continue`).
#   c15 — `--no-autostash` does NOT qualify for rule 2: switching git's own
#         stash-operate-restore OFF must face the live check.
#   c16 — rule 3 on `git pull`, the third history op, with no chain at all.
#   c17 — rule 1: a `git merge` merely MENTIONED in an echo is not a history op,
#         so the check must stay silent. This is the control that stops the new
#         rule from buying its recall by denying everything.
cat > "$TMP/c14.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git rebase --continue"},"cwd":"$REPO"}
EOF
cat > "$TMP/c15.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git pull --no-autostash"},"cwd":"$REPO"}
EOF
cat > "$TMP/c16.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git pull"},"cwd":"$REPO"}
EOF
cat > "$TMP/c17.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"echo 'remember to git merge feature-x after the review'"},"cwd":"$REPO"}
EOF
# ── r9: the parse holes that survived r8's deletion of the simulator ────────
# r8 removed every PREDICTION about what the shell would do, and that held —
# round 9 found no way to make a dirty tree read as clean. What it found
# instead is that the small amount of PARSING still required (which segment is
# a git invocation, which words are git's globals, whether the op is exempt)
# had holes, and each one skipped the tree reading entirely.
#
#   c18 — rule 2 was a SUBSTRING search over the joined, already-unquoted
#         segment, so an exempt token appearing inside an option VALUE switched
#         the whole check off. Executed on a dirty fixture, `git merge -m "wip
#         --autostash later" feature` was ALLOWED. The exemption is now exact
#         TOKEN equality with value-taking options' values skipped.
#   c19 — the control for that fix: a REAL `--autostash` must still be exempt
#         even when a -m value also names an exempt flag, so recall was not
#         bought with a false deny.
#   c20 — a segment was tested for git by its FIRST WORD only, so any shell
#         compound keyword in front of the op hid it. `if true; then git merge
#         x; fi` was SILENT while bare `git merge x` DENIED, and the merge ran
#         over uncommitted work in the fixture.
#   c21 — the grouping form of the same hole, attached-paren spelling.
#   c22 — the loop form, plus an UNRESOLVABLE `-C $d`: an unreadable named
#         directory used to be treated as clean and ALLOWED; it now degrades to
#         reading the event cwd.
#   c23 — the clean-tree half of the b3/b4 global-option hole.
#   c24 — the r8-DISCLOSED bare command wrapper, now closed: a `git` word is
#         searched for ALONG the segment, not only at its head.
#   c25 — a RELATIVE `-C` was resolved against the HOOK PROCESS's cwd instead
#         of the event's, so `git -C . pull` in a dirty repo A was judged
#         against whatever repo B the hook sat in. Fired deliberately from the
#         OTHER checkout so the two directories differ.
#   c26 — a trailing shell COMMENT put an exempt token on the invocation.
cat > "$TMP/c18.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git merge -m \"wip --autostash later\" feature-x"},"cwd":"$REPO"}
EOF
cat > "$TMP/c19.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git merge --autostash -m \"keep --skip in the message\" feature-x"},"cwd":"$REPO"}
EOF
cat > "$TMP/c20.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"if true; then git merge feature-x; fi"},"cwd":"$REPO"}
EOF
cat > "$TMP/c21.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git status && (git merge feature-x)"},"cwd":"$REPO"}
EOF
cat > "$TMP/c22.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"for d in .; do git -C \$d pull; done"},"cwd":"$REPO"}
EOF
cat > "$TMP/c23.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git --no-optional-locks pull"},"cwd":"$REPO"}
EOF
cat > "$TMP/c24.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"timeout 300 git pull"},"cwd":"$REPO"}
EOF
cat > "$TMP/c25.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git -C . merge feature-x"},"cwd":"$REPO"}
EOF
cat > "$TMP/c26.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git pull origin main  # finish the --continue later"},"cwd":"$REPO"}
EOF

if [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]; then
    fire git-guardrails.py "$TMP/c1.json"
    expect_deny   "c1 merge on a DIRTY tree is denied"
    fire git-guardrails.py "$TMP/c2.json"
    expect_silent "c2 --abort stays allowed (it is how you get OUT of a dirty merge)"
    fire git-guardrails.py "$TMP/c4.json"
    expect_deny   "c4 ACCEPTED COST: git stash push && git merge in ONE command is now DENIED on a dirty tree (the guard reads the tree, it does not simulate the chain — run the two as separate commands). Pinned so it is not 'fixed' back"
    fire git-guardrails.py "$TMP/c5.json"
    expect_deny   "c5 quoted git -C <path> merge on a DIRTY tree is still denied"
    fire git-guardrails.py "$TMP/c6.json"
    expect_deny   "c6 git commit && git merge on a DIRTY tree is denied (no segment licenses a later op)"
    fire git-guardrails.py "$TMP/c7.json"
    expect_deny   "c7 git stash push && touch <file> && git merge on a DIRTY tree is denied (r6 bypass shape)"
    fire git-guardrails.py "$TMP/c8.json"
    expect_deny   "c8 git -C <other clean repo> stash && git merge on a DIRTY tree is denied (r6 bypass shape — the op's OWN cwd is what is read)"
    fire git-guardrails.py "$TMP/c9.json"
    expect_silent "c9 git merge --autostash on a DIRTY tree is allowed (git stashes, merges and restores itself — it establishes the precondition)"
    fire git-guardrails.py "$TMP/c10.json"
    expect_deny   "c10 git stash push && echo note > <tracked file> && git merge is denied (r7 bypass shape)"
    fire git-guardrails.py "$TMP/c11.json"
    expect_deny   "c11 r8: cd <other repo> && git merge on a DIRTY session tree is denied (a cd cannot make the tree the guard reads look clean)"
    fire git-guardrails.py "$TMP/c12.json"
    expect_deny   "c12 r8: git stash push && echo \$(touch f) && git merge is denied (a command substitution inside an 'inert' word used to preserve the clean mark)"
    fire git-guardrails.py "$TMP/c13.json"
    expect_deny   "c13 r8: the backtick spelling of the same substitution is denied"
    fire git-guardrails.py "$TMP/c14.json"
    expect_silent "c14 git rebase --continue on a DIRTY tree is allowed (rule 2 escape form, on a different op)"
    fire git-guardrails.py "$TMP/c15.json"
    expect_deny   "c15 git pull --no-autostash on a DIRTY tree is denied (turning git's own autostash OFF does not qualify for the rule-2 exemption)"
    fire git-guardrails.py "$TMP/c16.json"
    expect_deny   "c16 bare git pull on a DIRTY tree is denied (rule 3 on the third history op)"
    fire git-guardrails.py "$TMP/c17.json"
    expect_silent "c17 clean control: a git merge merely MENTIONED in an echo is not a history op — the check stays silent (rule 1)"
    fire git-guardrails.py "$TMP/c18.json"
    expect_deny   "c18 r9: an exempt token inside an option VALUE (git merge -m \"wip --autostash later\") no longer satisfies rule 2 — the exemption is exact-token, not substring"
    fire git-guardrails.py "$TMP/c19.json"
    expect_silent "c19 r9 control: a REAL --autostash is still exempt even when a -m value also names an exempt flag (the c18 fix did not buy recall with a false deny)"
    fire git-guardrails.py "$TMP/c20.json"
    expect_deny   "c20 r9: a compound-command keyword in front of the op (if true; then git merge x; fi) no longer hides it from the check"
    fire git-guardrails.py "$TMP/c21.json"
    expect_deny   "c21 r9: the grouping form of the same hole (git status && (git merge x)) is denied"
    fire git-guardrails.py "$TMP/c22.json"
    expect_deny   "c22 r9: the loop form with an UNRESOLVABLE -C (for d in .; do git -C \$d pull; done) is denied — an unreadable named directory degrades to the event cwd instead of allowing"
    fire git-guardrails.py "$TMP/c23.json"
    expect_deny   "c23 r9: an unenumerated git global option on a history op (git --no-optional-locks pull) is denied"
    fire git-guardrails.py "$TMP/c24.json"
    expect_deny   "c24 r9: the r8-disclosed bare command wrapper (timeout 300 git pull) is now SEEN and denied"
    fire_in "$OTHER_REPO" git-guardrails.py "$TMP/c25.json"
    expect_deny   "c25 r9: a RELATIVE -C is resolved against the EVENT cwd, not the hook process's — fired from the other checkout, git -C . merge on the dirty event repo is denied"
    fire git-guardrails.py "$TMP/c26.json"
    expect_deny   "c26 r9: an exempt token inside a trailing shell COMMENT does not exempt the op"
else
    no "c1 merge on a DIRTY tree is denied" "fixture repo did not come up dirty"
    no "c2 --abort stays allowed" "fixture repo did not come up dirty"
    no "c4 ACCEPTED COST: stash-then-merge in ONE command is denied" "fixture repo did not come up dirty"
    no "c5 quoted git -C merge on a DIRTY tree is denied" "fixture repo did not come up dirty"
    no "c6 git commit && git merge on a DIRTY tree is denied" "fixture repo did not come up dirty"
    no "c7 git stash push && touch <file> && git merge on a DIRTY tree is denied" "fixture repo did not come up dirty"
    no "c8 git -C <other clean repo> stash && git merge on a DIRTY tree is denied" "fixture repo did not come up dirty"
    no "c9 git merge --autostash on a DIRTY tree is allowed" "fixture repo did not come up dirty"
    no "c10 git stash push && echo note > <file> && git merge is denied" "fixture repo did not come up dirty"
    no "c11 cd <other repo> && git merge on a DIRTY session tree is denied" "fixture repo did not come up dirty"
    no "c12 command substitution inside an inert word && git merge is denied" "fixture repo did not come up dirty"
    no "c13 backtick substitution && git merge is denied" "fixture repo did not come up dirty"
    no "c14 git rebase --continue on a DIRTY tree is allowed" "fixture repo did not come up dirty"
    no "c15 git pull --no-autostash on a DIRTY tree is denied" "fixture repo did not come up dirty"
    no "c16 bare git pull on a DIRTY tree is denied" "fixture repo did not come up dirty"
    no "c17 clean control: a mentioned git merge stays silent" "fixture repo did not come up dirty"
    no "c18 an exempt token inside an option VALUE does not exempt the op" "fixture repo did not come up dirty"
    no "c19 control: a REAL --autostash is still exempt" "fixture repo did not come up dirty"
    no "c20 a compound-command keyword does not hide the op" "fixture repo did not come up dirty"
    no "c21 the grouping form is denied" "fixture repo did not come up dirty"
    no "c22 the loop form with an unresolvable -C is denied" "fixture repo did not come up dirty"
    no "c23 an unenumerated git global option on a history op is denied" "fixture repo did not come up dirty"
    no "c24 a bare command wrapper (timeout 300 git pull) is denied" "fixture repo did not come up dirty"
    no "c25 a relative -C is resolved against the EVENT cwd" "fixture repo did not come up dirty"
    no "c26 an exempt token inside a trailing comment does not exempt the op" "fixture repo did not come up dirty"
fi

git -C "$REPO" add untracked.txt >/dev/null 2>&1
# commit.gpgsign=true / tag.gpgsign=true in a global config would make this
# commit fail on a machine that signs by default (no usable key in the hook's
# non-interactive environment); pin them off, the same defensive posture as the
# identity flags, so the fixture reaches a clean tree for case c3.
git -C "$REPO" -c commit.gpgsign=false -c tag.gpgsign=false \
    -c user.email=battery@example.invalid -c user.name=hook-battery \
    commit -q -m "seed" >/dev/null 2>&1
if [ -z "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]; then
    fire git-guardrails.py "$TMP/c1.json"
    expect_silent "c3 clean control: the same merge on a CLEAN tree is allowed"
else
    no "c3 clean control: the same merge on a CLEAN tree is allowed" \
       "fixture repo would not go clean"
fi

# ── (d) claim-reconcile ────────────────────────────────────────────────────
# One synthetic passport, one claim: produced by an analysis script, shown in
# two places. Editing the producer stales it; editing one display puts it out
# of step with the other; editing an unrelated file must say nothing.
echo ""
echo "  (d) claim-reconcile.py — numeric claims a just-edited file can stale"

PROJ="$TMP/proj"
mkdir -p "$PROJ/quality_reports/passports" "$PROJ/scripts"
cat > "$PROJ/quality_reports/passports/demo.yaml" <<'EOF'
claims:
  - id: C1
    description: headline estimate
    source_file: scripts/analysis.R
    location: paper.tex
    appears_in:
      - path: paper.tex
      - path: slides.qmd
EOF
: > "$PROJ/scripts/analysis.R"
: > "$PROJ/paper.tex"
: > "$PROJ/slides.qmd"
: > "$PROJ/notes.md"

cat > "$TMP/d1.json" <<EOF
{"tool_name":"Edit","tool_input":{"file_path":"$PROJ/scripts/analysis.R"},"cwd":"$PROJ"}
EOF
cat > "$TMP/d2.json" <<EOF
{"tool_name":"Edit","tool_input":{"file_path":"$PROJ/paper.tex"},"cwd":"$PROJ"}
EOF
cat > "$TMP/d3.json" <<EOF
{"tool_name":"Edit","tool_input":{"file_path":"$PROJ/notes.md"},"cwd":"$PROJ"}
EOF

# HOME is redirected so the hook's per-session throttle state lands in the temp
# directory: no leftovers, and no earlier run can throttle this one into silence.
fire claim-reconcile.py "$TMP/d1.json" HOME="$TMP" CLAUDE_PROJECT_DIR="$PROJ"
expect_contains "d1 editing the source script flags the claim STALE" "STALE"
fire claim-reconcile.py "$TMP/d2.json" HOME="$TMP" CLAUDE_PROJECT_DIR="$PROJ"
expect_contains "d2 editing one display warns the others may disagree" "disagree"
fire claim-reconcile.py "$TMP/d3.json" HOME="$TMP" CLAUDE_PROJECT_DIR="$PROJ"
expect_silent   "d3 clean control: a file no passport mentions is silent"

# ── verdict ────────────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "hook-battery: ALL PASS ($TOTAL cases)"
    exit 0
fi
echo "hook-battery: $FAIL of $TOTAL cases FAILED:"
for f in "${FAILED[@]}"; do echo "  - $f"; done
echo "A guard that no longer fires is worse than no guard: it looks like coverage."
exit 1

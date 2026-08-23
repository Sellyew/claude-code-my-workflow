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
# ISOLATION IS NOT `git -C`. This battery runs inside `.githooks/pre-commit`,
# and git EXPORTS its repository into a hook's environment: GIT_DIR,
# GIT_INDEX_FILE, GIT_WORK_TREE, GIT_COMMON_DIR, GIT_OBJECT_DIRECTORY,
# GIT_PREFIX, GIT_NAMESPACE and siblings. GIT_DIR overrides repository
# DISCOVERY; `-C` only changes the working directory. From a LINKED WORKTREE
# those variables are ABSOLUTE, so the fixture's `init`/`add`/`commit` operated
# on the USER'S repository — writing a junk `seed` commit onto their branch,
# leaving a phantom deletion in their tree, and aborting the commit that
# triggered the hook. (Found by /blast-radius, 2026-08-23; reproduced end to
# end from a linked worktree of a fresh clone.) The whole GIT_* namespace is
# therefore stripped below before any fixture is built, and cases e1-e3 pin it.
#
# HOOK_DIR overrides which hook directory is exercised. That is how the battery
# itself is qualified: point it at a stub guard that always allows and it must
# go red, because a battery that cannot fail is decoration.
#
# Exit 0 = every case passed. Exit 1 = at least one case failed (named on
# stdout). Exit 2 = the battery could not run, which is a failure, not a pass.
set -uo pipefail

# ── strip the inherited git environment (see header) ───────────────────────
# Prefix-based, not a fixed list: a git version that adds one more
# repository-scoping variable must not silently re-open the hole. Only
# GIT_EXEC_PATH is kept — it locates git's own helper programs, not a
# repository. Names are listed here for grep-ability, but the loop is what
# enforces it: GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR
# GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX
# GIT_NAMESPACE GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM
# GIT_GRAFT_FILE GIT_ATTR_SOURCE GIT_CONFIG_* GIT_INDEX_VERSION.
for _gv in ${!GIT_@}; do
    [ "$_gv" = "GIT_EXEC_PATH" ] && continue
    unset "$_gv"
done
unset _gv
# The same names, spelled for `env -u` in fire()/fire_in() below. The strip
# above already covers every child, so this is the second, explicit layer: it
# survives someone re-exporting one of these mid-script.
UNSET_GIT_ENV=(-u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR
               -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES
               -u GIT_PREFIX -u GIT_NAMESPACE -u GIT_CEILING_DIRECTORIES
               -u GIT_DISCOVERY_ACROSS_FILESYSTEM -u GIT_GRAFT_FILE
               -u GIT_ATTR_SOURCE -u GIT_INDEX_VERSION)

DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if [ -z "${DIR:-}" ] || [ ! -d "$DIR" ]; then
    echo "hook-battery: cannot resolve script directory" >&2; exit 2
fi
ROOT="$(cd "$DIR/.." && pwd)"
HOOKS="${HOOK_DIR:-$ROOT/.claude/hooks}"
SELF_PATH="$DIR/$(basename "$0")"   # absolute; cases e1-e3 re-enter this script

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

# ── --fixture-selftest: the child half of cases e1-e3 ──────────────────────
# Cases e1-e3 re-enter THIS script with git's hook environment deliberately
# exported at a decoy repository, and check that the fixture build lands in the
# fixture. It has to be a re-entry rather than an inline subshell: the defect
# was that the strip above did not exist, so the only honest way to exercise it
# is to run the real top-of-script path in a contaminated environment. Builds
# one fixture repo, commits in it, prints its HEAD, exits.
if [ "${1:-}" = "--fixture-selftest" ]; then
    SELF="$TMP/selftest-repo"
    mkdir -p "$SELF" || exit 2
    git -C "$SELF" init -q >/dev/null 2>&1
    : > "$SELF/untracked.txt"
    git -C "$SELF" add untracked.txt >/dev/null 2>&1
    git -C "$SELF" -c commit.gpgsign=false -c tag.gpgsign=false \
        -c user.email=battery@example.invalid -c user.name=hook-battery \
        commit -q -m "seed" >/dev/null 2>&1
    if [ -n "$(git -C "$SELF" status --porcelain 2>/dev/null)" ]; then
        echo "selftest-fixture-not-clean"; exit 1
    fi
    git -C "$SELF" rev-parse HEAD 2>/dev/null || { echo "selftest-no-head"; exit 1; }
    exit 0
fi

PASS=0; FAIL=0; FAILED=()
ok() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); FAILED+=("$1"); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

OUT=""; RC=0
fire() {  # fire <hook-file> <event-json> [VAR=VAL ...]  -> sets OUT, RC
    # The GIT_* strip is repeated here (it is already done process-wide) because
    # a CASE may deliberately re-export one — c27/c28 do, to prove the guard
    # reads the directory it was ASKED about. `env` applies -u first and the
    # trailing VAR=VAL assignments second, so a case that wants one back gets it.
    local hook="$1" ev="$2"; shift 2
    OUT="$(env -u ALLOW_ROOT_OF_TRUST_WRITE -u ALLOW_DIRTY_MERGE -u CLAUDE_STRICT_PATHS \
           "${UNSET_GIT_ENV[@]}" "$@" python3 "$HOOKS/$hook" < "$ev" 2>/dev/null)"
    RC=$?
}
fire_in() {  # fire_in <hook-process-cwd> <hook-file> <event-json> -> sets OUT, RC
    # The hook PROCESS's working directory is not the event's `cwd`: hooks are
    # spawned by the CLI process while the Bash tool's directory drifts. Case
    # c25 needs the two to DIFFER, so it runs the guard from somewhere else.
    local dir="$1" hook="$2" ev="$3"
    OUT="$(cd "$dir" && env -u ALLOW_ROOT_OF_TRUST_WRITE -u ALLOW_DIRTY_MERGE \
           -u CLAUDE_STRICT_PATHS "${UNSET_GIT_ENV[@]}" \
           python3 "$HOOKS/$hook" < "$ev" 2>/dev/null)"
    RC=$?
}

verdict() {  # verdict <text> — hand a LOCALLY computed result to the expect_
             # helpers, so a case that does not fire a hook (section (e), which
             # tests the battery's own isolation) is still counted and reported
             # through the same three helpers as every other case.
    OUT="$1"; RC=0
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

# a25/a26: SCOPE — THIS project, not the pattern wherever it appears on the
# machine. `is_protected()` matched path TEXT with no repository anchoring, so
# the guard denied writes into ANY tree containing `.claude/hooks` or
# `.githooks`: a throwaway fixture clone, a second checkout, the user's own
# ~/.claude — while its deny message asserted the path was "part of THIS
# repository's root of trust". It bought no protection (this repo's gates are
# not in those trees) and it BLOCKED the qualification ledger's own gate-9
# reproduction, whose seeded defect is a mistyped hook path written into a
# fixture clone's settings.json. A path now counts only when it resolves inside
# the project (CLAUDE_PROJECT_DIR → the repo the call runs in → the repo this
# hook ships in); if none resolves, the guard falls back to the text match and
# says so. a25 pins that the real project path is still denied when the event
# carries an explicit cwd; a26 pins that the fixture-clone write is allowed.
mkdir -p "$TMP/rot-clone/.claude/hooks" "$TMP/rot-clone/.githooks"
printf '{}\n' > "$TMP/rot-clone/.claude/settings.json"
cat > "$TMP/a25.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"printf disabled > .claude/settings.json"},"cwd":"$ROOT"}
EOF
cat > "$TMP/a26.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"sed -i '' 's/notify.sh/notifyy.sh/' $TMP/rot-clone/.claude/settings.json"},"cwd":"$ROOT"}
EOF
fire root-of-trust-guard.py "$TMP/a25.json"
expect_deny   "a25 a write into THIS project's root of trust is denied when the event names its cwd"
fire root-of-trust-guard.py "$TMP/a26.json"
expect_silent "a26 the same write into a fixture clone OUTSIDE the project is allowed (the ledger's gate-9 reproduction)"

# a27-a30 (r12): BACKSLASH-NEWLINE LINE CONTINUATION. `_TOKEN` listed `\n` as a
# separator while its word class could not consume backslash+newline, so an
# ordinary multi-line command was read as TWO segments and the half carrying the
# protected path was never scored. Executed against the pre-fix guard: a `rm -f`
# whose operand sat on the continued line emitted NO decision, and the same
# string through `bash -c` really deleted `.claude/hooks/git-guardrails.py`;
# continued `cp`/`mv`/redirection into `settings.json` were silent too, while
# every one-line spelling DENIED — the guarantee turned on where the author had
# put a newline. Continuations are now spliced before tokenising. The two
# controls are the other direction, and neither is padding:
#   a29 — a REAL newline with no backslash must still SEPARATE commands, so a
#         later READ is not folded into an earlier deleter's argument list.
#   a30 — an ESCAPED backslash (a literal `\` argument) before a real newline is
#         NOT a continuation. A naive `\\\n -> " "` join splices here and turns
#         a29's shape into a false DENY; the fix consumes even backslash runs
#         first, so only an odd trailing backslash joins.
#
# The JSON spellings these four turn on, defined once because the escaping is
# where such a fixture goes quietly wrong: a JSON string carries a backslash as
# `\\` and a newline as `\n`.
JCONT='\\\n'      # `\` + newline  — a POSIX LINE CONTINUATION (joins the line)
JNL='\n'          # a bare newline — an ordinary command SEPARATOR
JBSNL='\\\\\n'    # `\\` + newline — a literal backslash, then a separator
cat > "$TMP/a27.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"rm -f ${JCONT}    .claude/hooks/git-guardrails.py"},"cwd":"$ROOT"}
EOF
cat > "$TMP/a28.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"printf disabled > ${JCONT}    .claude/settings.json"},"cwd":"$ROOT"}
EOF
cat > "$TMP/a29.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"rm -f /tmp/hook-battery-no-such-file${JNL}cat .claude/settings.json"},"cwd":"$ROOT"}
EOF
cat > "$TMP/a30.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"rm -f /tmp/hook-battery-no-such-file${JBSNL}cat .claude/settings.json"},"cwd":"$ROOT"}
EOF
fire root-of-trust-guard.py "$TMP/a27.json"
expect_deny   "a27 r12: a DELETE of a protected path written across a LINE CONTINUATION is denied (this exact spelling went silent and really removed the guard file)"
fire root-of-trust-guard.py "$TMP/a28.json"
expect_deny   "a28 r12: a REDIRECTION into settings.json across a line continuation is denied (the quote-stripped backstop sees the joined line too)"
fire root-of-trust-guard.py "$TMP/a29.json"
expect_silent "a29 r12 control: a GENUINE newline still separates commands — a following read is not folded into the preceding rm's arguments"
fire root-of-trust-guard.py "$TMP/a30.json"
expect_silent "a30 r12 control: an ESCAPED backslash before a real newline is a literal backslash, not a continuation — the newline still separates (a naive backslash-newline join would false-deny here)"

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

# b15-b17 (r12): the SAME backslash-newline defect as a27-a30, one hook over —
# `_SEG_TOKEN` listed `\n` as a separator and its word class could not consume
# backslash+newline, so a destructive flag that landed on the continued line was
# invisible. Executed against the pre-fix guard on a dirty fixture, all SILENT:
# `git clean \`+NL+`-xfd` (and run through bash it deleted the untracked file),
# `git push \`+NL+`--force origin main`, `git reset \`+NL+`--hard HEAD~1`,
# `git add \`+NL+`-A`, `git checkout \`+NL+`-- .`, `git restore \`+NL+`.`. Every
# one-line spelling denied. b17 is the control in the other direction: the join
# must not start denying the SAFE flag just because it was continued.
cat > "$TMP/b15.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git clean ${JCONT}    -xfd"}}
EOF
cat > "$TMP/b16.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git push ${JCONT}--force origin main"}}
EOF
cat > "$TMP/b17.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git push ${JCONT}--force-with-lease origin main"}}
EOF
fire git-guardrails.py "$TMP/b15.json"
expect_deny   "b15 r12: a destructive clean whose -xfd sits on a CONTINUED line is denied (this spelling was silent and deleted untracked files)"
fire git-guardrails.py "$TMP/b16.json"
expect_deny   "b16 r12: the same for a continued force push (git push \\<newline>--force origin main)"
fire git-guardrails.py "$TMP/b17.json"
expect_silent "b17 r12 control: the continued SAFE spelling (git push \\<newline>--force-with-lease) stays allowed — splicing continuations did not buy recall by denying every multi-line push"

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

# A THIRD checkout, dirty in a way `git stash` can actually handle: ONE TRACKED
# file modified, and no `??` entry anywhere. r13 needs this because `--autostash`
# stopped being unconditionally exempt — it is now allowed only when porcelain
# status reports no untracked entry — so the ALLOW direction of that rule cannot
# be tested in $REPO, whose entire dirt IS an untracked file. Cases c19, c30 and
# c42 run here; c9 is the same op in $REPO and must now DENY.
TRACKED_REPO="$TMP/tracked-repo"
mkdir -p "$TRACKED_REPO"
git -C "$TRACKED_REPO" init -q >/dev/null 2>&1
printf 'v1\n' > "$TRACKED_REPO/tracked.txt"
git -C "$TRACKED_REPO" add tracked.txt >/dev/null 2>&1
git -C "$TRACKED_REPO" -c commit.gpgsign=false -c tag.gpgsign=false \
    -c user.email=battery@example.invalid -c user.name=hook-battery \
    commit -q -m "seed" >/dev/null 2>&1
printf 'v2\n' > "$TRACKED_REPO/tracked.txt"   # ` M tracked.txt`, no `??`

# ── r8, AS AMENDED AT r13: the rule this block pins ────────────────────────
# The clean-tree check STOPPED SIMULATING THE SHELL at r8, and r13 corrected two
# things r8 got wrong. What it pins NOW, rule by rule:
#   (0) an identified history op must be a STANDALONE SIMPLE COMMAND, or it is
#       DENIED without reading the tree (r13). The reading is taken at
#       PreToolUse, so a chain, pipeline, redirection, substitution, `cd` or
#       assignment could act between the reading and git.
#   (1) no history op as an actual command → silent.
#   (2) an ESCAPE op (`--abort`/`--continue`/`--skip`/`--quit`/`--edit-todo`)
#       → ALLOW without reading the tree. `--autostash` was in this list until
#       r13 and is NOT any more: it reads the tree and is allowed only when
#       there is no `??` entry, because git's autostash does not stash
#       untracked files (c9 flipped to DENY; c42 is its control).
#   (3) otherwise read `git status --porcelain` LIVE in the directory the
#       invocation itself names and DENY if it is non-empty. An UNRESOLVED
#       repository selector denies too, rather than falling back (r13).
# r8's own heading called this "a closed whole-command allowlist". It was not —
# an unidentified invocation (`bash -c '...'`) passes outside the rule entirely.
# Corrected wording lives in the guard's docstring; see the r13 block below.
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
# ALLOWED (the remedy the old deny message recommended). It is DENIED — since
# r13 by RULE 0, before the tree is read at all, because a history op is
# accepted only as a standalone simple command. Eight rounds of trying to
# SIMULATE what the first half of such a chain would do leaked eight times,
# including `git stash` not stashing UNTRACKED files at all, so this very chain
# could leave the tree dirty and still be allowed. Note what r13 added: the
# mirror image, `<a write> && git merge`, was ALLOWED on a clean tree the whole
# time (c31) — the cost below was being paid in one direction only.
# The cost is one extra TOOL CALL (run the two commands separately, which the
# guard re-checks), not one keystroke. DO NOT "fix" this back.
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
# c14-c17: the rest of the rule.
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
{"tool_name":"Bash","tool_input":{"command":"git merge --autostash -m \"keep --skip in the message\" feature-x"},"cwd":"$TRACKED_REPO"}
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
# ── the INHERITED GIT ENVIRONMENT (found by /blast-radius, 2026-08-23) ──────
# `tree_is_dirty()` shells out to `git status --porcelain` with a cwd and,
# until this fix, no `env=`. git EXPORTS GIT_DIR / GIT_INDEX_FILE into every
# hook it runs, ABSOLUTE when the commit came from a linked worktree — and
# GIT_DIR overrides repository DISCOVERY, so `cwd=` was decoration: the guard
# answered about whatever repository the environment named. Cases c1-c26 were
# green in that environment FOR THE WRONG REASON — satisfied by reading the
# session's own dirty repository rather than the fixture. Both directions are
# pinned, because a fix that simply denied more would also have "passed" c27:
#   c27 — event cwd DIRTY, environment pointing at a CLEAN repo  -> DENY
#   c28 — event cwd CLEAN, environment pointing at the DIRTY one -> SILENT
# c28 is the one that cannot be satisfied by over-denying.
#
# Both cases export GIT_WORK_TREE as well as GIT_DIR/GIT_INDEX_FILE, and that
# is not padding: with GIT_DIR alone git still takes the WORKING TREE from the
# process cwd, so the answer coincides with the right one and BOTH cases pass
# against the unfixed guard — measured. Only when the environment names the
# other repository COMPLETELY do the two readings disagree, which is what makes
# these cases able to fail.
cat > "$TMP/c28.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git merge feature-x"},"cwd":"$OTHER_REPO"}
EOF
# c29/c30 (r12): the clean-tree half of the line-continuation defect. With the
# subcommand on the continued line the segment holding `git` had no subcommand
# at all, so rule 1 answered "not a history op" and the tree was never read —
# `git \`+NL+`merge feature-x` and `git \`+NL+`pull origin main` were SILENT on
# the dirty fixture. c30 is the control the auditor asked for and it discriminates
# in BOTH directions: with the continuation unspliced the exempt `--autostash`
# lands in a SEPARATE segment, so the merge segment looks unexempt and DENIES —
# a false deny of git's own stash-operate-restore. Splicing restores both.
cat > "$TMP/c29.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git ${JCONT}merge feature-x"},"cwd":"$REPO"}
EOF
cat > "$TMP/c30.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git merge ${JCONT}--autostash feature-x"},"cwd":"$TRACKED_REPO"}
EOF

if [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]; then
    fire git-guardrails.py "$TMP/c1.json"
    expect_deny   "c1 merge on a DIRTY tree is denied"
    fire git-guardrails.py "$TMP/c2.json"
    expect_silent "c2 --abort stays allowed (it is how you get OUT of a dirty merge)"
    fire git-guardrails.py "$TMP/c4.json"
    expect_deny   "c4 ACCEPTED COST: git stash push && git merge in ONE command is DENIED — at r13 by RULE 0 (a history op is accepted only as a STANDALONE simple command), before the tree is even read. Run the two as separate commands. Pinned so it is not 'fixed' back"
    fire git-guardrails.py "$TMP/c5.json"
    expect_deny   "c5 quoted git -C <path> merge on a DIRTY tree is still denied"
    fire git-guardrails.py "$TMP/c6.json"
    expect_deny   "c6 git commit && git merge on a DIRTY tree is denied (no segment licenses a later op)"
    fire git-guardrails.py "$TMP/c7.json"
    expect_deny   "c7 git stash push && touch <file> && git merge on a DIRTY tree is denied (r6 bypass shape)"
    fire git-guardrails.py "$TMP/c8.json"
    expect_deny   "c8 git -C <other clean repo> stash && git merge on a DIRTY tree is denied (r6 bypass shape — the op's OWN cwd is what is read)"
    fire git-guardrails.py "$TMP/c9.json"
    expect_deny   "c9 r13 (referee finding 1): git merge --autostash on a tree whose dirt is an UNTRACKED file is now DENIED — git's autostash does not stash untracked files, so it does NOT establish the precondition this check enforces. This case was expect_silent until r13, on a claim the referee reproduced as false"
    fire git-guardrails.py "$TMP/c10.json"
    expect_deny   "c10 git stash push && echo note > <tracked file> && git merge is denied (r7 bypass shape)"
    fire git-guardrails.py "$TMP/c11.json"
    expect_deny   "c11 r8/r13: cd <other repo> && git merge is denied — r8 because a cd cannot make the tree the guard reads look clean, r13 because a `cd` on a history op's command line now violates RULE 0 outright"
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
    expect_silent "c19 r9 control, MOVED to the tracked-dirt fixture at r13: a REAL --autostash is still allowed even when a -m value also names an exempt flag — over TRACKED dirt, which is what git's autostash actually handles"
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
    fire git-guardrails.py "$TMP/c1.json" GIT_WORK_TREE="$OTHER_REPO" \
         GIT_DIR="$OTHER_REPO/.git" GIT_INDEX_FILE="$OTHER_REPO/.git/index"
    expect_deny   "c27 the INHERITED git environment does not answer for the event cwd: GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE pointing at a CLEAN repo, merge in the DIRTY event repo is still denied"
    fire git-guardrails.py "$TMP/c28.json" GIT_WORK_TREE="$REPO" \
         GIT_DIR="$REPO/.git" GIT_INDEX_FILE="$REPO/.git/index"
    expect_silent "c28 the control for c27, which over-denying cannot satisfy: GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE pointing at the DIRTY repo, merge in a CLEAN event repo stays allowed"
    fire git-guardrails.py "$TMP/c29.json"
    expect_deny   "c29 r12: a history op whose SUBCOMMAND sits on a CONTINUED line (git \\<newline>merge feature-x) on a DIRTY tree is denied — the continuation used to split it into two segments and the tree was never read"
    fire git-guardrails.py "$TMP/c30.json"
    expect_silent "c30 r12 control, MOVED to the tracked-dirt fixture at r13: a continued --autostash (git merge \\<newline>--autostash feature-x) over TRACKED dirt is still allowed — unspliced, the exempt token lands in a SEPARATE segment, which now fails RULE 0 as well as the exemption test"
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
    no "c27 an inherited GIT_DIR does not answer for the event cwd (deny direction)" "fixture repo did not come up dirty"
    no "c28 an inherited GIT_DIR does not answer for the event cwd (allow direction)" "fixture repo did not come up dirty"
    no "c29 a history op with its subcommand on a CONTINUED line is denied on a dirty tree" "fixture repo did not come up dirty"
    no "c30 control: a continued --autostash is still exempt" "fixture repo did not come up dirty"
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


# ── (c) continued — r13: ENFORCEMENT AT EXECUTION TIME, NOT AT HOOK TIME ----
# An independent frontier-model referee (2026-08-23) found the defect eleven
# in-house rounds missed, because every one of them tested chains in ONE
# direction. This hook decides at PreToolUse -- BEFORE bash runs the command --
# so the referee's case, on a CLEAN repository:
#
#     printf '\n# local work\n' >> analysis.R && git merge main
#
# reads clean at hook time and is dirty when git executes. Rounds 4-12 DENIED the
# chain that CLEANED the tree (c4) and ALLOWED the chain that DIRTIED it: the
# whole false-deny cost, none of the safety, while the docstring's summary and
# law 20 both claimed the stronger guarantee. A history op is therefore accepted
# only as a STANDALONE SIMPLE COMMAND (rule 0) -- a genuinely closed grammar over
# the text the parser sees, rather than a best-effort search for cleaners.
#
# These cases run on the CLEAN fixtures on purpose. On a dirty tree every one of
# them would deny for the ordinary reason and the block could not discriminate at
# all; on a clean tree, a deny can ONLY come from the rule under test. c32, c36,
# c39 and c42 are the controls, and they are what stops rule 0 from being
# satisfied by a guard that denies everything.
cat > "$TMP/c31.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"printf 'x' >> analysis.R && git merge feature-x"},"cwd":"$OTHER_REPO"}
EOF
cat > "$TMP/c32.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git merge feature-x"},"cwd":"$OTHER_REPO"}
EOF
cat > "$TMP/c33.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git pull | tail -5"},"cwd":"$OTHER_REPO"}
EOF
cat > "$TMP/c34.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git merge \$(cat /tmp/hook-battery-branch-name)"},"cwd":"$OTHER_REPO"}
EOF
cat > "$TMP/c35.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git merge --abort && echo done"},"cwd":"$OTHER_REPO"}
EOF
cat > "$TMP/c36.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git merge -m \"wip && later\" feature-x"},"cwd":"$OTHER_REPO"}
EOF
cat > "$TMP/c37.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git -C \"\$TARGET_REPO\" merge feature-x"},"cwd":"$OTHER_REPO"}
EOF
cat > "$TMP/c38.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git -C /tmp/hook-battery-no-such-repo merge feature-x"},"cwd":"$OTHER_REPO"}
EOF
cat > "$TMP/c39.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git -C $OTHER_REPO merge feature-x"},"cwd":"$OTHER_REPO"}
EOF
cat > "$TMP/c40.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git --git-dir=$REPO/.git --work-tree=$REPO merge feature-x"},"cwd":"$OTHER_REPO"}
EOF
cat > "$TMP/c41.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"GIT_DIR=$REPO/.git GIT_WORK_TREE=$REPO git merge feature-x"},"cwd":"$OTHER_REPO"}
EOF

if [ -z "$(git -C "$OTHER_REPO" status --porcelain 2>/dev/null)" ]; then
    fire git-guardrails.py "$TMP/c31.json"
    expect_deny   "c31 r13 THE REFEREE'S FAILING CASE: a write (printf >> analysis.R) chained before a history op is DENIED even though the tree is CLEAN right now -- the tree it reads is not the tree git will see. Allowed before r13"
    fire git-guardrails.py "$TMP/c32.json"
    expect_silent "c32 r13 CONTROL: the same op as a STANDALONE simple command on the same CLEAN tree is allowed -- rule 0 did not buy its recall by denying every history op"
    fire git-guardrails.py "$TMP/c33.json"
    expect_deny   "c33 r13: a PIPELINE carrying a history op is denied on a clean tree (another command runs in the same job)"
    fire git-guardrails.py "$TMP/c34.json"
    expect_deny   "c34 r13: a COMMAND SUBSTITUTION in the op's arguments is denied on a clean tree -- it executes before git does, and r8 already measured \$(touch f) writing to the tree"
    fire git-guardrails.py "$TMP/c35.json"
    expect_deny   "c35 r13: an ESCAPE flag does not license a CHAIN -- git merge --abort && echo done is denied, while the standalone spelling (c2) stays allowed"
    fire git-guardrails.py "$TMP/c36.json"
    expect_silent "c36 r13 CONTROL: shell metacharacters INSIDE a quoted option value are text, not syntax -- git merge -m \"wip && later\" is still allowed on a clean tree, so the rule-0 scan is quote-aware and did not regress to substring matching"
    fire git-guardrails.py "$TMP/c37.json"
    expect_contains "c37 r13 (referee finding 2): an UNRESOLVED -C target denies instead of falling back to the event cwd -- git -C \"\$TARGET_REPO\" with the variable unexpanded, fired from a CLEAN event repo, was SILENT before r13 because the guard read the wrong repository and liked what it saw" \
                    "from that repository, or spell the path literally"
    fire git-guardrails.py "$TMP/c38.json"
    expect_deny   "c38 r13: the same for a -C naming a directory that simply does not exist -- an unanswered question is not an allow"
    fire git-guardrails.py "$TMP/c39.json"
    expect_silent "c39 r13 CONTROL: a -C that DOES resolve, at a clean repository, is still allowed -- denying unresolved selectors did not become denying every -C"
    fire git-guardrails.py "$TMP/c40.json"
    expect_deny   "c40 r13 (referee finding 3): --git-dir/--work-tree select a DIFFERENT repository with no -C and no cd (the referee reproduced native git doing it), so a history op carrying them is denied. Both repositories are CLEAN here, so nothing but the selector rule can produce this deny"
    fire git-guardrails.py "$TMP/c41.json"
    expect_deny   "c41 r13 (referee finding 3, environment form): GIT_DIR=/GIT_WORK_TREE= on the command line select another repository just as directly; every NAME=VALUE assignment on a history op's line is refused, so a future GIT_* variable cannot re-open this"
else
    no "c31 the referee's write-then-op chain is denied on a clean tree" "the OTHER_REPO fixture did not come up clean"
    no "c32 control: a standalone op on a clean tree is allowed" "the OTHER_REPO fixture did not come up clean"
    no "c33 a pipeline carrying a history op is denied" "the OTHER_REPO fixture did not come up clean"
    no "c34 a command substitution in the op's arguments is denied" "the OTHER_REPO fixture did not come up clean"
    no "c35 an escape flag does not license a chain" "the OTHER_REPO fixture did not come up clean"
    no "c36 control: quoted metacharacters are text, not syntax" "the OTHER_REPO fixture did not come up clean"
    no "c37 an unresolved -C target denies" "the OTHER_REPO fixture did not come up clean"
    no "c38 a -C naming a missing directory denies" "the OTHER_REPO fixture did not come up clean"
    no "c39 control: a resolvable -C at a clean repo is allowed" "the OTHER_REPO fixture did not come up clean"
    no "c40 --git-dir/--work-tree on a history op is denied" "the OTHER_REPO fixture did not come up clean"
    no "c41 GIT_DIR=/GIT_WORK_TREE= on a history op is denied" "the OTHER_REPO fixture did not come up clean"
fi

# c42: the ALLOW direction of the r13 --autostash rule, which c9 alone cannot
# show. c9 proves --autostash is refused over UNTRACKED dirt; c42 proves it is
# still accepted over TRACKED dirt, which is exactly what git's stash handles.
# Without this case the referee's fix could have been "delete the exemption",
# and the battery could not tell the two choices apart.
cat > "$TMP/c42.json" <<EOF
{"tool_name":"Bash","tool_input":{"command":"git merge --autostash feature-x"},"cwd":"$TRACKED_REPO"}
EOF
TRACKED_STATUS="$(git -C "$TRACKED_REPO" status --porcelain 2>/dev/null)"
if [ -n "$TRACKED_STATUS" ] && ! printf '%s\n' "$TRACKED_STATUS" | grep -q '^??'; then
    fire git-guardrails.py "$TMP/c42.json"
    expect_silent "c42 r13 CONTROL for c9: git merge --autostash over dirt that is ONE MODIFIED TRACKED FILE and no ?? entry is still allowed -- the referee's correction narrowed the exemption to what git's autostash really handles, it did not delete it"
else
    no "c42 control: --autostash over tracked-only dirt is still allowed" \
       "the TRACKED_REPO fixture is not modified-tracked-only (status: ${TRACKED_STATUS:-<empty>})"
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

# ── (e) the battery's own isolation from git's hook environment ────────────
# This battery runs INSIDE .githooks/pre-commit. Everything above is worthless
# if the battery's own fixtures escape into the repository the hook was fired
# from — and for one release they did: `git -C <fixture>` does not isolate
# against an exported GIT_DIR, so from a linked worktree the fixture's
# init/add/commit wrote a junk `seed` commit onto the USER'S branch, left a
# phantom deletion in their tree, and aborted their commit on every retry.
#
# The check re-enters this script with git's hook environment exported at a
# DECOY repository — the same two variables git really exports, absolute, as
# they arrive from a linked worktree — and then asks the decoy three questions.
#
# The three verdicts are computed here and handed to `expect_contains` through
# `verdict`, rather than calling ok/no directly, because the derived-counts
# gate counts `expect_` CALL SITES as the case count and the battery prints
# PASS+FAIL: a case that skips the helpers makes those two numbers disagree,
# which is the drift that gate exists to stop. Exactly three calls are made on
# every path, including the one where the decoy repo cannot be built.
echo ""
echo "  (e) hook-battery.sh — isolation from the git environment it runs inside"

DECOY="$TMP/decoy"
mkdir -p "$DECOY"
git -C "$DECOY" init -q >/dev/null 2>&1
: > "$DECOY/keep.txt"
git -C "$DECOY" add keep.txt >/dev/null 2>&1
git -C "$DECOY" -c commit.gpgsign=false -c tag.gpgsign=false \
    -c user.email=battery@example.invalid -c user.name=hook-battery \
    commit -q -m "decoy baseline" >/dev/null 2>&1
DECOY_HEAD_BEFORE="$(git -C "$DECOY" rev-parse HEAD 2>/dev/null)"

E1=""; E2=""; E3=""
if [ -z "$DECOY_HEAD_BEFORE" ]; then
    E1="DECOY-REPO-UNUSABLE: it would not reach a baseline commit"
    E2="$E1"; E3="$E1"
else
    SELFTEST_OUT="$(GIT_DIR="$DECOY/.git" GIT_INDEX_FILE="$DECOY/.git/index" \
                    GIT_PREFIX="" bash "$SELF_PATH" --fixture-selftest 2>/dev/null)"
    SELFTEST_RC=$?
    DECOY_HEAD_AFTER="$(git -C "$DECOY" rev-parse HEAD 2>/dev/null)"
    DECOY_STATUS="$(git -C "$DECOY" status --porcelain 2>/dev/null)"

    # e1: the fixture's own commit must be UNREACHABLE from the inherited
    # repository — not merely "a different sha". Before the fix the child
    # printed a real sha too; it was just the decoy's, freshly written.
    if [ "$SELFTEST_RC" -ne 0 ] || [ -z "$SELFTEST_OUT" ]; then
        E1="FIXTURE-BUILD-FAILED: the self-test exited $SELFTEST_RC saying '${SELFTEST_OUT:-<empty>}' (the user's own commit fails the same way)"
    elif git -C "$DECOY" cat-file -e "${SELFTEST_OUT}^{commit}" 2>/dev/null; then
        E1="FIXTURE-COMMIT-LANDED-IN-THE-INHERITED-REPO: $SELFTEST_OUT exists there, so the exported GIT_DIR was honoured"
    else
        E1="fixture-commit-absent-from-inherited-repo"
    fi

    if [ "$DECOY_HEAD_AFTER" = "$DECOY_HEAD_BEFORE" ]; then
        E2="inherited-HEAD-unmoved"
    else
        E2="INHERITED-HEAD-MOVED: $DECOY_HEAD_BEFORE -> $DECOY_HEAD_AFTER"
    fi

    if [ -z "$DECOY_STATUS" ]; then
        E3="inherited-tree-untouched"
    else
        E3="INHERITED-TREE-DIRTIED: $DECOY_STATUS"
    fi
fi

verdict "$E1"
expect_contains "e1 a fixture built under git's hook environment commits into the FIXTURE, not into the repository the environment names" \
                "fixture-commit-absent-from-inherited-repo"
verdict "$E2"
expect_contains "e2 the inherited repository's HEAD is untouched (no junk 'seed' commit lands on the user's branch)" \
                "inherited-HEAD-unmoved"
verdict "$E3"
expect_contains "e3 the inherited repository's working tree is untouched (no phantom deletion left behind)" \
                "inherited-tree-untouched"

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

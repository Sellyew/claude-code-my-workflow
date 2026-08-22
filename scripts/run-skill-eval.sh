#!/usr/bin/env bash
# run-skill-eval.sh — measure whether a skill produces better output than not having it.
#
#   ./scripts/run-skill-eval.sh <skill-name> <cases-dir> [--replicates N]
#
# Answers the question the eight backtest gates cannot: those prove the repo is
# internally consistent and currently true; this asks whether a skill's
# INSTRUCTIONS actually help.
#
# Method (the baseline comparison):
#   for each case, run the prompt in a FRESH session WITH the skill and WITHOUT it,
#   grade both against the case's assertions, and report the delta.
#
# A fresh session matters: leftover context from authoring a skill masks gaps in
# what the skill actually says. You will believe it states something it only implied.
#
# MUST be run from a normal shell, not from inside a Claude Code session —
# nested `claude -p` fails with error_during_execution.
set -uo pipefail

SKILL="${1:-}"; CASES="${2:-}"; REPS=3   # N=1 measures sampling noise, not the skill
[ "${3:-}" = "--replicates" ] && REPS="${4:-1}"

if [ -z "$SKILL" ] || [ -z "$CASES" ]; then
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2
fi
command -v claude >/dev/null || { echo "eval: claude CLI not found" >&2; exit 2; }
[ -d "$CASES" ] || { echo "eval: cases dir '$CASES' not found" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"      # resolved BEFORE any cd
OUT="$ROOT/quality_reports/qualification/evals/$SKILL"
mkdir -p "$OUT"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
RESULTS="$OUT/$STAMP.jsonl"

# Smoke-test the harness before spending eval effort — and FAIL FAST.
# A nested `claude -p` (i.e. run from inside a Claude Code session) does not
# error immediately, it hangs. Without a timeout this script appears to work
# and then sits there, which is the worst of both.
echo "── smoke test: can we run headless at all? ──"
SMOKE="$(timeout 45 claude -p "Reply with exactly: OK" --output-format text 2>/dev/null || true)"
if ! grep -q "OK" <<<"$SMOKE"; then
    echo "" >&2
    echo "eval: headless \`claude -p\` is not working here." >&2
    echo "      Most likely you are running this INSIDE a Claude Code session — nested" >&2
    echo "      sessions fail with error_during_execution. Run it from a normal shell." >&2
    exit 2
fi
echo "  ok"

# ── MANIPULATION CHECK ─────────────────────────────────────────────────────────
# The one question that decides whether every number below means anything:
# DID THE MANIPULATION ACTUALLY HAPPEN? If both arms are identical, we are
# comparing baseline to baseline and any delta is noise wearing a lab coat.
#
# Verified 2026-08-21: `--settings skillOverrides`, a `Skill(name)` deny rule, and
# `--disallowedTools Skill` all FAIL to remove a project skill in headless mode.
# `--setting-sources user` does remove it (project skills stop loading).
# This check exists because a prior version of this harness silently compared
# baseline against baseline and produced a clean, low-variance, entirely false result.
# BEHAVIORAL manipulation check.
#
# Self-report probes ("can you see skill X? YES/NO") proved non-deterministic in
# BOTH single-shot and best-of-3 forms — the same question answered 1, then 0,
# then 1 across an hour. Asking a model about its own tool inventory is not a
# measurement.
#
# Instead: make each arm PROVE it by explicit invocation. `/skill <question>`
# forces the skill file into context in the with-arm; in the without-arm
# (--setting-sources user) the skill does not exist, so the invocation cannot
# draw on its content. We check for a MARKER: a distinctive string that appears
# in the skill's own files and nowhere in the model's general knowledge.
# Per-skill marker: evals/marker.txt line 1 = question, line 2 = expected substring.
# Falls back to a generic ask-for-verbatim-heading probe.
MARKER_FILE="$(dirname "$CASES")/marker.txt"
if [ -f "$MARKER_FILE" ]; then
    MARKER_Q="$(sed -n 1p "$MARKER_FILE")"
    MARKER_EXPECT="$(sed -n 2p "$MARKER_FILE")"
else
    MARKER_Q="Quote verbatim the first markdown heading (the line starting with #) of your skill instructions."
    MARKER_EXPECT="$(grep -m1 '^# ' ".claude/skills/$SKILL/SKILL.md" | sed 's/^# //' | cut -c1-40)"
fi
echo "── manipulation check (behavioral: retrieve a fact only the skill contains) ──"
ON_RESP="$(timeout 180 claude -p "/$SKILL $MARKER_Q" --output-format text 2>/dev/null)"
OFF_RESP="$(timeout 180 claude -p "/$SKILL $MARKER_Q" --setting-sources user --output-format text 2>/dev/null)"
ON=0; OFF=0
grep -qiF "$MARKER_EXPECT" <<<"$ON_RESP"  && ON=1
grep -qiF "$MARKER_EXPECT" <<<"$OFF_RESP" && OFF=1
echo "  marker retrieved: with=$ON  without=$OFF"
if [ "$ON" = "0" ]; then
    echo "eval: ABORT — the WITH arm could not retrieve the skill's own marker phrase." >&2
    echo "      Either the skill is not loading under /$SKILL invocation, or MARKER_Q/" >&2
    echo "      MARKER_EXPECT do not match this skill — set a per-skill marker." >&2
    exit 3
fi
if [ "$OFF" = "1" ]; then
    echo "eval: ABORT — the WITHOUT arm retrieved the marker anyway; the disable did" >&2
    echo "      not take, so the arms are not genuinely different." >&2
    exit 3
fi
echo "  ok — with-arm proves skill access; without-arm demonstrably lacks it"

pass=0; total=0; pass_off=0
for case_file in "$CASES"/*.md; do
    [ -f "$case_file" ] || continue
    name="$(basename "$case_file" .md)"
    # README.md documents the case format; it is not a case. Without this the
    # harness graded the docs and scored 0/6, which looks like a failing skill.
    [ "$name" = "README" ] && continue
    # A case must actually have both sections, or it silently contributes 0.
    if ! grep -q '^## Prompt' "$case_file" || ! grep -q '^## Assert' "$case_file"; then
        echo "  SKIP $name: missing '## Prompt' or '## Assert'" >&2
        continue
    fi
    prompt="$(sed -n '/^## Prompt/,/^## Assert/p' "$case_file" | sed '1d;$d')"
    asserts="$(sed -n '/^## Assert/,$p' "$case_file" | sed '1d' | grep -c '^- ')"
    case_with=0; case_without=0
    for r in $(seq 1 "$REPS"); do
        for mode in with without; do
            if [ "$mode" = "with" ]; then
                resp="$(timeout 180 claude -p "/$SKILL $prompt" --output-format text 2>/dev/null)"
            else
                # --setting-sources user is the mechanism verified to actually drop
                # project skills; skillOverrides / deny rules / --disallowedTools do not.
                resp="$(timeout 180 claude -p "$prompt" --setting-sources user --output-format text 2>/dev/null)"
            fi
            # Each assertion line may list ALTERNATIVES separated by " | ".
            # A correct answer phrased differently must still count; single-substring
            # grading was too brittle for open prose and produced false misses.
            hits=0
            while IFS= read -r a; do
                a="${a#- }"; [ -z "$a" ] && continue
                matched=0
                IFS='|' read -ra ALTS <<< "$a"
                for alt in "${ALTS[@]}"; do
                    alt="$(echo "$alt" | sed 's/^ *//; s/ *$//')"
                    [ -z "$alt" ] && continue
                    if grep -qiF -- "$alt" <<<"$resp"; then matched=1; break; fi
                done
                # A case named nottrigger-* INVERTS the test: the assertion must be ABSENT.
                case "$name" in
                    nottrigger-*) [ "$matched" -eq 0 ] && hits=$((hits+1)) ;;
                    *)            [ "$matched" -eq 1 ] && hits=$((hits+1)) ;;
                esac
            done < <(sed -n '/^## Assert/,$p' "$case_file" | grep '^- ')
            printf '{"case":"%s","rep":%s,"mode":"%s","hits":%s,"asserts":%s}\n' \
                   "$name" "$r" "$mode" "$hits" "$asserts" >> "$RESULTS"
            if [ "$mode" = "with" ]; then
                total=$((total+asserts)); pass=$((pass+hits)); case_with=$((case_with+hits))
            else
                pass_off=$((pass_off+hits)); case_without=$((case_without+hits))
            fi
        done
    done
    echo "  $name: with=$case_with/$((asserts*REPS))  without=$case_without/$((asserts*REPS))"
done

echo ""
echo "── result (N=$REPS replicates per case) ──"
echo "  with skill:    $pass / $total assertions"
echo "  without skill: $pass_off / $total assertions"
echo "  delta:         $((pass - pass_off)) assertions"
echo "  raw:           $RESULTS"
echo ""
python3 - "$RESULTS" <<'PYEOF'
import json, sys, collections, statistics
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
by = collections.defaultdict(list)
for r in rows: by[(r["case"], r["mode"])].append(r["hits"])
print("")
print("── per-case variance across replicates ──")
noisy = []
for (case, mode), hits in sorted(by.items()):
    if mode != "with": continue
    off = by.get((case, "without"), [])
    sd = statistics.pstdev(hits) if len(hits) > 1 else 0.0
    flag = ""
    if len(hits) > 1 and sd > 0.5:
        flag = "  <-- HIGH VARIANCE, result not interpretable"
        noisy.append(case)
    print(f"  {case:<34} with={hits} (sd={sd:.2f})  without={off}{flag}")
if noisy:
    print("")
    print(f"  {len(noisy)} case(s) are too noisy to interpret. Raise replicates or")
    print("  rewrite the assertions before recording anything in the ledger.")
    sys.exit(3)
print("")
print("  Variance acceptable. Record a row in quality_reports/qualification/LEDGER.md.")
print("  An eval with no recorded baseline is an anecdote.")
PYEOF

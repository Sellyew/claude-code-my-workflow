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

SKILL="${1:-}"; CASES="${2:-}"; REPS=1
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

pass=0; total=0; pass_off=0
for case_file in "$CASES"/*.md; do
    [ -f "$case_file" ] || continue
    name="$(basename "$case_file" .md)"
    prompt="$(sed -n '/^## Prompt/,/^## Assert/p' "$case_file" | sed '1d;$d')"
    asserts="$(sed -n '/^## Assert/,$p' "$case_file" | sed '1d' | grep -c '^- ')"
    for r in $(seq 1 "$REPS"); do
        for mode in with without; do
            if [ "$mode" = "with" ]; then
                resp="$(claude -p "$prompt" --output-format text 2>/dev/null)"
            else
                resp="$(claude -p "$prompt" --settings '{"skillOverrides":{"'"$SKILL"'":"off"}}' --output-format text 2>/dev/null)"
            fi
            hits=0
            while IFS= read -r a; do
                a="${a#- }"; [ -z "$a" ] && continue
                grep -qiF -- "$a" <<<"$resp" && hits=$((hits+1))
            done < <(sed -n '/^## Assert/,$p' "$case_file" | grep '^- ')
            printf '{"case":"%s","rep":%s,"mode":"%s","hits":%s,"asserts":%s}\n' \
                   "$name" "$r" "$mode" "$hits" "$asserts" >> "$RESULTS"
            if [ "$mode" = "with" ]; then
                total=$((total+asserts)); pass=$((pass+hits))
            else
                pass_off=$((pass_off+hits))
            fi
        done
    done
    echo "  $name: with=$pass/$total"
done

echo ""
echo "── result ──"
echo "  with skill:    $pass / $total assertions"
echo "  without skill: $pass_off / $total assertions"
echo "  delta:         $((pass - pass_off)) assertions"
echo "  raw:           $RESULTS"
echo ""
echo "Record a row in quality_reports/qualification/LEDGER.md. An eval with no"
echo "recorded baseline is an anecdote."

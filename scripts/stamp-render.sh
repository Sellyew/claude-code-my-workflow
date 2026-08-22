#!/usr/bin/env bash
# Record which source produced the current rendered artifacts — and what those
# artifacts were, byte-for-byte, at stamp time.
#
# git does not preserve mtimes, so currency cannot be answered by timestamps.
# And a source-only stamp is not enough either (Codex, PR #140 round 2): if you
# render guide/ but forget to sync docs/, or hand-edit an HTML file, a stamp
# that records only the source hash still matches. So each line binds an output
# path to BOTH the source fingerprint and that output's own fingerprint.
#
# Run after: quarto render + cp guide/workflow-guide.html docs/workflow-guide.html
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"      # resolved BEFORE any cd
SRC="$ROOT/guide/workflow-guide.qmd"
G="$ROOT/guide/workflow-guide.html"
D="$ROOT/docs/workflow-guide.html"
for f in "$SRC" "$G" "$D"; do
    [ -f "$f" ] || { echo "stamp-render: missing $f" >&2; exit 2; }
done
# The invariant behind stamping both: docs/ IS a copy of guide/. Refuse to
# stamp a divergent pair — that is the exact failure the stamp exists to catch.
if ! cmp -s "$G" "$D"; then
    echo "stamp-render: REFUSING — guide/ and docs/ HTML differ." >&2
    echo "  sync first:  cp guide/workflow-guide.html docs/workflow-guide.html" >&2
    exit 1
fi
SH="$(shasum -a 256 "$SRC" | cut -c1-16)"
GH="$(shasum -a 256 "$G"   | cut -c1-16)"
DH="$(shasum -a 256 "$D"   | cut -c1-16)"
{
  echo "guide/workflow-guide.html:$SH:$GH"
  echo "docs/workflow-guide.html:$SH:$DH"
} > "$ROOT/.render-stamp"
echo "stamp-render: source=$SH output=$GH (guide/docs identical, both stamped)"

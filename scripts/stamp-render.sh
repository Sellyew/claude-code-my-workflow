#!/usr/bin/env bash
# Record which source produced the current rendered artifacts.
#
# git does not preserve mtimes, so "is the render current?" cannot be answered by
# timestamps — on a fresh clone the checkout order decides. This writes a content
# fingerprint of the SOURCE, which travels with the repo and is true everywhere.
#
# Run after every `quarto render`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"      # resolved BEFORE any cd
SRC="$ROOT/guide/workflow-guide.qmd"
[ -f "$SRC" ] || { echo "stamp-render: $SRC not found" >&2; exit 2; }
H="$(shasum -a 256 "$SRC" | cut -c1-16)"
{
  echo "guide/workflow-guide.html:$H"
  echo "docs/workflow-guide.html:$H"
} > "$ROOT/.render-stamp"
echo "stamp-render: recorded source fingerprint $H"

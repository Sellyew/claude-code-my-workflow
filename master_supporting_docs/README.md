# Supporting documents

Source material this project builds on — papers, existing slide decks, reference PDFs, prior
drafts. **Read-only inputs, not working files.**

## What belongs here

- Papers you are teaching from, replicating, or refereeing.
- Existing decks or notes being ported into `Slides/` or `Quarto/`.
- Reference material an agent should be able to read but never edit.

## What does NOT belong here

- Anything you are actively editing — that lives in `Slides/`, `Quarto/`, or `scripts/`.
- Generated output — that lives in `scripts/*/_outputs/` or `docs/`.
- Scratch or experimental work — that lives in `explorations/`, or outside the repo entirely.

## Rules

1. **Read-only.** If a file here needs changing, it has become a working file: move it.
2. **Provenance.** For anything downloaded or received, note where it came from and when —
   a filename is not provenance. Use `templates/PROVENANCE.md` when the material is a
   reference oracle rather than background reading.
3. **Supersession is explicit.** When a newer version arrives, keep the predecessor and mark
   which is current. Silent overwrite destroys the record of what an earlier analysis used.
4. **Nothing confidential.** Restricted-use data and materials under a DUA never enter the
   repo — see [`.claude/rules/confidential-data.md`](../.claude/rules/confidential-data.md).

## Why this README exists

`scripts/check-repo-hygiene.py` requires every archive directory to explain itself. An archive
nobody can interpret is indistinguishable from abandoned clutter, and abandoned clutter is what
makes a repo feel unmaintained even when the code is fine.

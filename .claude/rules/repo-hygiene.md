# Repo Hygiene — scratch must not become main

Agents try things. Claude and Codex will each explore five approaches to a problem, and four of
them produce files. **Those four must not survive.** A repo where every abandoned attempt was
left in place is not a record of the work — it is noise that makes the real work unfindable,
and it is the single fastest way for a project to feel unmaintained while the code is fine.

Enforced by `scripts/check-repo-hygiene.py`, which runs inside `./scripts/backtest.sh` and
therefore on every commit.

## The rule

> **Anything you would not defend in a code review does not get committed as a main file.**

Three destinations, and everything goes to exactly one:

| Destination | For | Committed? |
|---|---|---|
| **The scratchpad** (outside the repo, or `explorations/`) | trying something; you do not yet know if it works | no (or `explorations/`, which is gitignored below the README) |
| **The working tree** (`Slides/`, `Quarto/`, `scripts/`, `.claude/`) | the approach you chose and would defend | yes |
| **An archive** (`master_supporting_docs/`, a dated `explorations/` subdir) | superseded work worth keeping for the record | yes, **with a README saying why** |

## What the checker rejects

- **Root clutter.** A file at the repository root that is not on the allowlist. Top-level space
  is for things a newcomer must see first; everything else lives in a directory.
- **Draft names.** `untitled*`, `tmp*`, `scratch*`, `foo*`, `test123*`.
- **Superseded copies.** `analysis_old.R`, `deck_backup.tex`, `notes_copy.md`. If it is worth
  keeping, archive it with a reason; otherwise delete it — **git already has the history.**
- **Version-in-filename.** `model_v2.R`, `paper_final.tex`, `script_fixed.py`. That is what git
  is for, and `_final` is never final.
- **Accidental duplicates.** `notes 2.md`, `data(1).csv` — the signature of a copy-paste or a
  download that nobody cleaned up.
- **Tracked build artifacts.** `.aux`, `.log`, `.synctex.gz`, `.pyc`. Regenerable output does
  not belong in version control.
- **Undocumented archives.** A directory holding superseded work with no README is
  indistinguishable from abandoned clutter.

*Numbered pipeline stages are exempt* — `01_explore.R`, `02_clean.R`, `03_analyze.R` are
idiomatic, not drafts.

## Archiving, not deleting

When work is superseded but the record matters — a prior specification, an approach that failed
for an interesting reason, a deck from a previous term:

1. Move it to a **dated** subdirectory: `explorations/2026-08_did-alternative-weighting/`.
2. Add a README with **three lines**: what this was, why it was superseded, and what replaced it.
3. Never edit it again. An archive that changes is not an archive.

> **A failed approach is evidence.** It tells the next person — often you — which routes are
> already closed. That is worth keeping, but only if it is labelled. An unlabelled dead end
> costs more than it saves.

## For agents specifically

- Write experiments to the session scratchpad, **not** the repo. If a scratch file must live in
  the repo to be run, put it under `explorations/` and delete it when done.
- **Never** create `foo_v2.R` beside `foo.R` to try something. Edit `foo.R`; git is the undo.
- When an approach is abandoned, **remove its files in the same commit** that lands the chosen
  approach. Do not leave both and let the reader guess which is live.
- If you are unsure whether something is scratch: it is scratch until it passes a gate.

## Cross-references

- [`.claude/rules/exploration-folder-protocol.md`](exploration-folder-protocol.md) — how `explorations/` is structured
- [`.claude/rules/meta-governance.md`](meta-governance.md) — what is committed vs local
- [`progress-reports.md`](progress-reports.md) — where the record of *work* lives, so files do not have to carry it

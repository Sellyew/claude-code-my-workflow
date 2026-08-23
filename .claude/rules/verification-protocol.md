---
paths:
  - "Slides/**/*.tex"
  - "Quarto/**/*.qmd"
  - "docs/**"
---

# Task Completion Verification Protocol

**At the end of EVERY task, Claude MUST verify the output works correctly.** This is non-negotiable.

## For Quarto/HTML Slides:
1. Run `./scripts/sync_to_docs.sh` (or `./scripts/sync_to_docs.sh LectureN`) to render and deploy
2. Open the HTML in browser: `open docs/slides/LectureX.html` (macOS) or `xdg-open` (Linux)
3. Verify images display by reading 2-3 image files to confirm valid content
4. Check HTML source for correct image paths
5. Check for overflow by scanning dense slides
6. Verify environment parity: every Beamer box environment has a CSS equivalent in the QMD
7. Report verification results

## For LaTeX/Beamer Slides:
1. Compile with xelatex and check for errors
2. Open the PDF to verify figures render (`open` on macOS, `xdg-open` on Linux)
3. Check for overfull hbox warnings

## For TikZ Diagrams in HTML/Quarto:
1. Browsers **cannot** display PDF images inline — ALWAYS convert to SVG
2. Use SVG (vector format) for crisp rendering: `pdf2svg input.pdf output.svg`
3. **NEVER use PNG for diagrams** — PNG is raster and looks blurry
4. Verify SVG files contain valid XML/SVG markup
5. Copy SVGs to `docs/Figures/LectureX/` via `sync_to_docs.sh`
6. **Freshness check:** Before using any TikZ SVG, verify extract_tikz.tex matches current Beamer source

## For R Scripts:
1. Run `Rscript scripts/R/filename.R`
2. Verify output files (PDF, RDS) were created with non-zero size
3. Spot-check estimates for reasonable magnitude

## Claims About Code Carry a Revision:

Any statement about what the code currently does carries the revision it was read at — the full standard lives in [`agent-authored-code.md`](agent-authored-code.md), which loads whenever a `.sh`/`.py`/`.R`/`.do` file is touched (this rule is scoped to slide/HTML deliverables, so the obligation belongs where code work actually happens).

## Common Pitfalls:
- **PDF images in HTML**: Browsers don't render PDFs inline → convert to SVG
- **Relative paths**: `../Figures/` works from `Quarto/` but not from `docs/slides/` → use `sync_to_docs.sh`
- **Assuming success**: Always verify output files exist AND contain correct content
- **Stale TikZ SVGs**: extract_tikz.tex diverges from Beamer source → always diff-check

## Verification Checklist:
```
[ ] Output file created successfully
[ ] No compilation/render errors
[ ] Images/figures display correctly
[ ] Paths resolve in deployment location (docs/)
[ ] Opened in browser/viewer to confirm visual appearance
[ ] Any claim about code state carries the revision it was read at
[ ] Reported results to user
```

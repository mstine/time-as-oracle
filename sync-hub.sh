#!/usr/bin/env bash
#
# sync-hub.sh — publish the Time as Oracle deck to the public hub, NOTES-FREE.
#
# Rebuilds the canonical presenting deck (~/.psyche/mystic-south/deck), strips
# every speaker note + the reveal notes plugin, copies the result into this
# repo's deck/, refreshes the PDF backup, and pushes to main (GitHub Pages).
#
# THE GUARANTEE: it verifies the public deck is notes-free and ABORTS before
# committing if any <aside class="notes"> survives. The hub can never re-leak
# the private speaker script (personal beats, facilitation cues, [placeholders]).
#
# The canonical deck (with notes, for presenting via 'S') is never modified.
#
# Usage:
#   ./sync-hub.sh              rebuild, strip, render PDF, verify, commit, push
#   ./sync-hub.sh --no-pdf     skip the (slow) PDF re-render
#   ./sync-hub.sh --no-push    stage + verify locally, do not commit/push
#
set -euo pipefail

CANON="$HOME/.psyche/mystic-south/deck"
HUB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUBDECK="$HUB/deck"

DO_PDF=1; DO_PUSH=1
for a in "$@"; do
  case "$a" in
    --no-pdf)  DO_PDF=0 ;;
    --no-push) DO_PUSH=0 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown arg: $a (try --help)" >&2; exit 2 ;;
  esac
done

[ -d "$CANON" ] || { echo "✖ canonical deck not found: $CANON" >&2; exit 1; }

echo "▸ rebuilding canonical deck…"
( cd "$CANON" && python3 build_deck.py )

if [ "$DO_PDF" = 1 ]; then
  echo "▸ re-rendering PDF backup…"
  ( cd "$CANON" && python3 render_deck.py ) || echo "  ⚠ PDF render failed — keeping the existing PDF"
fi

echo "▸ stripping speaker notes into the public deck…"
CANON="$CANON" HUBDECK="$HUBDECK" python3 - <<'PY'
import os, re, pathlib
canon   = pathlib.Path(os.environ["CANON"])
hubdeck = pathlib.Path(os.environ["HUBDECK"])
src = (canon / "index.html").read_text()
out = re.sub(r'<aside class="notes">.*?</aside>', '', src, flags=re.DOTALL)  # drop all notes
out = out.replace('<script src="reveal/notes/notes.js"></script>\n', '')      # drop notes plugin
out = re.sub(r'plugins:\s*\(typeof RevealNotes[^\n]*\)', 'plugins: []', out)   # drop registration
(hubdeck / "index.html").write_text(out)
(hubdeck / "print.html").write_text((canon / "print.html").read_text())        # print is already note-free
if (canon / "deck.css").read_text() != (hubdeck / "deck.css").read_text():
    (hubdeck / "deck.css").write_text((canon / "deck.css").read_text())
PY

cp "$CANON/time-as-oracle-deck.pdf" "$HUB/slides/time-as-oracle-deck.pdf"

echo "▸ verifying the public deck is notes-free…"
IDX="$HUBDECK/index.html"
notes=$(grep -c 'class="notes"' "$IDX" || true)
plug=$(grep -Ec 'notes/notes\.js|RevealNotes' "$IDX" || true)
slides=$(grep -c '<section ' "$IDX" || true)
if [ "$notes" != "0" ] || [ "$plug" != "0" ]; then
  echo "✖ ABORT: public deck still contains speaker notes (aside=$notes plugin=$plug). NOT pushing." >&2
  exit 1
fi
if [ "$slides" -lt 1 ]; then
  echo "✖ ABORT: public deck has no slides. NOT pushing." >&2
  exit 1
fi
echo "  ✓ notes=0  plugin=0  slides=$slides"

if [ "$DO_PUSH" = 0 ]; then
  echo "▸ --no-push: staged + verified locally, not pushing."
  exit 0
fi

echo "▸ committing + pushing…"
cd "$HUB"
git add deck/index.html deck/print.html deck/deck.css slides/time-as-oracle-deck.pdf
if git diff --cached --quiet; then
  echo "  nothing changed — hub already up to date."
  exit 0
fi
git commit -q -m "hub: sync notes-free deck + PDF (sync-hub.sh)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push origin main
echo "  ✓ pushed to main — GitHub Pages will redeploy in ~1 min."

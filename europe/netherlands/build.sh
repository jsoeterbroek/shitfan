#!/usr/bin/env bash
# Build PDF and ZIM from the Dutch Markdown source of truth.
#
# Usage: ./build.sh [all|pdf|zim] [OUTDIR]
#        ./build.sh              -> PDF + ZIM in the current directory
#        ./build.sh zim dist/    -> only the ZIM, written to dist/
#
# Output file names include the version from ./VERSION, e.g.
#   nederland-noodreferentie-0.1.pdf
#   nederland-noodreferentie-0.1.zim
#
# Requirements: pandoc, weasyprint (only for pdf), zimwriterfs, and either
# ImageMagick 7 (`magick`) or ImageMagick 6 (`convert`) for the ZIM illustration.
set -euo pipefail
cd "$(dirname "$0")"

# Pandoc and WeasyPrint emit UTF-8; without a UTF-8 locale the PDF title and
# other metadata come out as mojibake (e.g. "Nederland ��� Noodreferentie").
if ! locale charmap 2>/dev/null | grep -qi 'utf-8'; then
  export LC_ALL=C.UTF-8
  export LANG=C.UTF-8
fi

SRC="nederland-noodreferentie.md"
TARGET="${1:-all}"
OUTDIR="${2:-.}"
mkdir -p "$OUTDIR"

# "0.1 (26/10/2026)" -> "0.1"; strip any surrounding whitespace.
VERSION="$(cut -d' ' -f1 VERSION | tr -d '[:space:]')"
SLUG="nederland-noodreferentie"   # version-independent identifier
BASE="${SLUG}-${VERSION}"          # file name carries the version
TITLE="Nederland — Noodreferentie"

# ImageMagick 7 uses `magick`, ImageMagick 6 only ships `convert`.
IM=""
if command -v magick >/dev/null 2>&1; then
  IM="magick"
elif command -v convert >/dev/null 2>&1; then
  IM="convert"
fi

# 48x48 PNG illustration, required by zimwriterfs.
make_illustration() {
  local out="$1"
  if [[ -n "$IM" ]]; then
    "$IM" -size 48x48 "xc:#1b4965" \
      -fill white -pointsize 16 -gravity center -annotate +0+0 'NL' "$out"
    return
  fi
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import PIL' 2>/dev/null; then
    python3 - "$out" <<'PY'
import sys
from PIL import Image, ImageDraw
img = Image.new("RGB", (48, 48), "#1b4965")
d = ImageDraw.Draw(img)
d.text((16, 18), "NL", fill="white")
img.save(sys.argv[1])
PY
    return
  fi
  # Last resort: a 1x1 PNG, inflated to 48x48 by zimwriterfs is not possible,
  # so fail loudly instead of producing a ZIM with a broken icon.
  echo "error: need ImageMagick or Python Pillow for the ZIM illustration" >&2
  return 1
}

if [[ "$TARGET" == "all" || "$TARGET" == "pdf" ]]; then
  pandoc "$SRC" -f markdown -t html5 -s \
    --toc --toc-depth=2 \
    --metadata title="$TITLE" \
    -c "$PWD/print.css" -o "${OUTDIR}/${BASE}.html"
  weasyprint "${OUTDIR}/${BASE}.html" "${OUTDIR}/${BASE}.pdf"
  rm -f "${OUTDIR}/${BASE}.html"
  echo "wrote ${OUTDIR}/${BASE}.pdf"
fi

if [[ "$TARGET" == "all" || "$TARGET" == "zim" ]]; then
  STAGE="$(mktemp -d)"
  trap 'rm -rf "$STAGE"' EXIT
  mkdir -p "$STAGE/content"
  pandoc "$SRC" -f markdown -t html5 -s --toc --toc-depth=2 \
    --metadata title="$TITLE" -o "$STAGE/content/index.html" </dev/null
  make_illustration "$STAGE/content/illustration.png"
  rm -f "${OUTDIR}/${BASE}.zim"
  zimwriterfs \
    --welcome=index.html \
    --illustration=illustration.png \
    --language=nld \
    --name="$SLUG" \
    --title="$TITLE" \
    --description="Noodreferentie Nederland: plannen en acties bij uitval van internet" \
    --longDescription="Nederland — Noodreferentie. Wat de Nederlandse overheid plant bij rampen, crises en oorlog, en wat jij moet doen als het internet, de stroom of het water uitvalt. Bevat alarmering, rampzenders, schuilen en evacueren, 18 scenario's, locaties, voorraden, recht en verzekeringen." \
    --tags="nederland;noodhulp;crisis;rampen;offline" \
    --creator="Project shitfan" \
    --publisher="Project shitfan" \
    "$STAGE/content" "${OUTDIR}/${BASE}.zim"
  echo "wrote ${OUTDIR}/${BASE}.zim"
fi

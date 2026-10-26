#!/usr/bin/env bash
# Build PDF and ZIM from the UK Markdown source of truth.
#
# Usage: ./build.sh [all|pdf|zim] [OUTDIR]
#        ./build.sh              -> PDF + ZIM in the current directory
#        ./build.sh zim dist/    -> only the ZIM, written to dist/
#
# Output file names include the version from ./VERSION, e.g.
#   united-kingdom-emergency-reference-0.1.pdf
#   united-kingdom-emergency-reference-0.1.zim
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

SRC="united-kingdom-emergency-reference.md"
TARGET="${1:-all}"
OUTDIR="${2:-.}"
mkdir -p "$OUTDIR"

# "0.1 (26/10/2026)" -> "0.1"; strip any surrounding whitespace.
VERSION="$(cut -d' ' -f1 VERSION | tr -d '[:space:]')"
SLUG="united-kingdom-emergency-reference"   # version-independent identifier
BASE="${SLUG}-${VERSION}"          # file name carries the version
TITLE="United Kingdom — Emergency Reference"
ZIM_TITLE="UK Emergency Reference"   # zimwriterfs limit: 30 characters

# ImageMagick 7 uses `magick`, ImageMagick 6 only ships `convert`.
IM=""
if command -v magick >/dev/null 2>&1; then
  IM="magick"
elif command -v convert >/dev/null 2>&1; then
  IM="convert"
fi

# 48x48 PNG illustration, required by zimwriterfs.
# ImageMagick 6 on some runners has no usable default font and fails with
# "unable to read font `(null)'", so resolve a font explicitly and fall back to
# a plain colour tile when text rendering is unavailable.
make_illustration() {
  local out="$1" font=""

  if [[ -n "$IM" ]]; then
    for candidate in \
      "$(fc-match -f '%{file}' 'DejaVu Sans' 2>/dev/null || true)" \
      /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf \
      /usr/share/fonts/dejavu/DejaVuSans.ttf; do
      if [[ -n "$candidate" && -f "$candidate" ]]; then
        font="$candidate"
        break
      fi
    done

    if [[ -n "$font" ]] && "$IM" -size 48x48 "xc:#1b4965" -font "$font" \
        -fill white -pointsize 16 -gravity center -annotate +0+0 'NL' "$out" 2>/dev/null \
        && [[ -s "$out" ]]; then
      return 0
    fi

    # No usable font: a solid tile is still a valid 48x48 PNG.
    if "$IM" -size 48x48 "xc:#1b4965" "$out" 2>/dev/null && [[ -s "$out" ]]; then
      echo "note: drew a plain illustration (no usable font found)" >&2
      return 0
    fi
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
    return 0
  fi

  # Fail loudly rather than producing a ZIM with a broken icon.
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
    --language=eng \
    --name="$SLUG" \
    --title="$ZIM_TITLE" \
    --description="UK emergency reference: plans and actions when the internet is down" \
    --longDescription="United Kingdom — Emergency Reference. What the UK government, devolved administrations and local responders plan for emergencies, and what to do when the internet, power or water fails. Covers alerts and radio, shelter and evacuation, 19 scenarios, locations, reserves, law and insurance." \
    --tags="uk;emergency;civil-contingencies;offline;resilience" \
    --creator="Project shitfan" \
    --publisher="Project shitfan" \
    "$STAGE/content" "${OUTDIR}/${BASE}.zim"
  echo "wrote ${OUTDIR}/${BASE}.zim"
fi

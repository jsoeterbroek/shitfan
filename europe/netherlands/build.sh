#!/usr/bin/env bash
# Build PDF and ZIM from the Dutch Markdown source of truth.
# Usage: ./build.sh            (markdown -> pdf + zim)
#        ./build.sh pdf        (pdf only)
# Requirements: pandoc, weasyprint, zimwriterfs
set -euo pipefail
cd "$(dirname "$0")"

SRC="nederland-noodreferentie.md"
VERSION="$(cut -d' ' -f1 VERSION)"
BASE="nederland-noodreferentie-${VERSION}"
TARGET="${1:-all}"

if [[ "$TARGET" == "all" || "$TARGET" == "pdf" ]]; then
  pandoc "$SRC" -f markdown -t html5 -s \
    --toc --toc-depth=2 \
    --metadata title="Nederland — Noodreferentie" \
    -c "$PWD/print.css" -o "/tmp/${BASE}.html"
  weasyprint "/tmp/${BASE}.html" "${BASE}.pdf"
  echo "wrote ${BASE}.pdf"
fi

if [[ "$TARGET" == "all" || "$TARGET" == "zim" ]]; then
  STAGE="$(mktemp -d)"
  mkdir -p "$STAGE/nl"
  pandoc "$SRC" -f markdown -t html5 -s --toc --toc-depth=2 \
    --metadata title="Nederland — Noodreferentie" -o "$STAGE/nl/index.html" </dev/null
  # 48x48 PNG illustration required by zimwriterfs.
  magick -size 48x48 xc:'#1b4965' \
    -fill white -pointsize 16 -gravity center -annotate +0+0 'NL' \
    "$STAGE/nl/illustration.png"
  rm -f "${BASE}.zim"
  zimwriterfs \
    --welcome=index.html \
    --illustration=illustration.png \
    --language=nld \
    --name="nederland-noodreferentie-${VERSION}" \
    --title="Nederland — Noodreferentie" \
    --description="Noodreferentie Nederland: plannen en acties bij uitval van internet" \
    --creator="Project shitfan" \
    --publisher="Project shitfan" \
    "$STAGE/nl" "${BASE}.zim"
  rm -rf "$STAGE"
  echo "wrote ${BASE}.zim"
fi

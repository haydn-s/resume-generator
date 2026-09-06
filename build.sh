#!/usr/bin/env bash
#
# Build a DOCX resume from Markdown.
#
#   ./build.sh                              resume.md      -> resume.docx
#   ./build.sh resume-acme.md               resume-acme.md -> resume-acme.docx
#   ./build.sh resume-acme.md Resume_Acme.docx
#
set -euo pipefail
cd "$(dirname "$0")"

SRC="${1:-resume.md}"
OUT="${2:-${SRC%.md}.docx}"

command -v pandoc >/dev/null || { echo "pandoc not found"; exit 1; }
if [ ! -f "$SRC" ]; then
  echo "no such file: $SRC" >&2
  [ -f resume.template.md ] && \
    echo "start from the template:  cp resume.template.md resume.md" >&2
  exit 1
fi

# Regenerate the style carrier if it is missing or out of date.
if [ ! -f reference.docx ] || [ make_reference.py -nt reference.docx ]; then
  python3 make_reference.py
fi

pandoc "$SRC" \
  --reference-doc=reference.docx \
  --lua-filter=rightalign.lua \
  -o "$OUT"

echo "wrote $OUT"

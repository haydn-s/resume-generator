#!/usr/bin/env bash
#
# Build a DOCX resume from Markdown.
#
#   ./build.sh                                      resume.md      -> resume.docx
#   ./build.sh resume-acme.md                       resume-acme.md -> resume-acme.docx
#   ./build.sh resume-acme.md Resume_Acme.docx
#   ./build.sh --preset roomy resume.md Roomy.docx
#
# Presets live in presets.ini. Each caches its own reference-<preset>.docx, so
# switching between presets does not force a rebuild of the others.
#
set -euo pipefail
cd "$(dirname "$0")"

PRESET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --preset)   [ $# -ge 2 ] || { echo "--preset needs a name" >&2; exit 1; }
                PRESET="$2"; shift 2 ;;
    --preset=*) PRESET="${1#*=}"; shift ;;
    --)         shift; break ;;
    -*)         echo "unknown option: $1" >&2; exit 1 ;;
    *)          break ;;
  esac
done

SRC="${1:-resume.md}"
OUT="${2:-${SRC%.md}.docx}"

command -v pandoc >/dev/null || { echo "pandoc not found"; exit 1; }
if [ ! -f "$SRC" ]; then
  echo "no such file: $SRC" >&2
  [ -f resume.template.md ] && \
    echo "start from the template:  cp resume.template.md resume.md" >&2
  exit 1
fi

# Rebuild the style carrier when it is missing or older than either the
# generator or the presets file. Without the presets.ini check, editing a
# preset would silently render with the previous values.
if [ -n "$PRESET" ]; then REF="reference-$PRESET.docx"; else REF="reference.docx"; fi
if [ ! -f "$REF" ] || [ make_reference.py -nt "$REF" ] || [ presets.ini -nt "$REF" ]; then
  if [ -n "$PRESET" ]; then
    python3 make_reference.py --preset "$PRESET" "$REF"
  else
    python3 make_reference.py "$REF"
  fi
fi

pandoc "$SRC" \
  --reference-doc="$REF" \
  --lua-filter=rightalign.lua \
  -o "$OUT"

echo "wrote $OUT${PRESET:+ [preset: $PRESET]}"

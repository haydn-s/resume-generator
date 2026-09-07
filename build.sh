#!/usr/bin/env bash
#
# Build a DOCX resume from Markdown.
#
#   ./build.sh                          resumes/resume.md -> resumes/out/resume.docx
#   ./build.sh resumes/acme.md          resumes/acme.md   -> resumes/out/acme.docx
#   ./build.sh resumes/acme.md resumes/out/Acme_Corp.docx
#   ./build.sh --preset roomy resumes/resume.md
#
# Presets live in presets.ini. Each caches its own build/reference-<preset>.docx,
# so switching between presets does not force a rebuild of the others.
#
# resumes/ is gitignored in full: your content and your output both stay local
# no matter what you name them.
#
set -euo pipefail
cd "$(dirname "$0")"

SRC_DIR=resumes
OUT_DIR=resumes/out
BUILD_DIR=build

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

SRC="${1:-$SRC_DIR/resume.md}"
if [ $# -ge 2 ]; then
  OUT="$2"
else
  base=$(basename "$SRC")
  OUT="$OUT_DIR/${base%.md}.docx"
fi

command -v pandoc >/dev/null || { echo "pandoc not found"; exit 1; }
if [ ! -f "$SRC" ]; then
  echo "no such file: $SRC" >&2
  [ -f templates/resume.template.md ] && \
    echo "start from the template:  cp templates/resume.template.md $SRC_DIR/resume.md" >&2
  exit 1
fi

if [ -n "$PRESET" ]; then REF="$BUILD_DIR/reference-$PRESET.docx"; else REF="$BUILD_DIR/reference.docx"; fi
mkdir -p "$BUILD_DIR" "$OUT_DIR"

# Rebuild the style carrier when it is missing or older than either the
# generator or the presets file. Without the presets.ini check, editing a
# preset would silently render with the previous values.
if [ ! -f "$REF" ] || [ tools/make_reference.py -nt "$REF" ] || [ presets.ini -nt "$REF" ]; then
  if [ -n "$PRESET" ]; then
    python3 tools/make_reference.py --preset "$PRESET" "$REF"
  else
    python3 tools/make_reference.py "$REF"
  fi
fi

pandoc "$SRC" \
  --reference-doc="$REF" \
  --lua-filter=tools/rightalign.lua \
  -o "$OUT"

echo "wrote $OUT${PRESET:+ [preset: $PRESET]}"

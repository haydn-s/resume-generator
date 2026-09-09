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

usage() {
  cat <<'USAGE'
usage: build.sh [options] [SOURCE] [OUTPUT]

Build a DOCX resume from Markdown.

arguments:
  SOURCE   markdown to build   (default: resumes/resume.md)
  OUTPUT   docx to write       (default: resumes/out/<source>.docx)

options:
  -p, --preset NAME    build with a named design preset from presets.ini
  -t, --template REF   use your own reference .docx instead of generating one.
                       A bare name resolves to templates/<name>.docx; anything
                       with a slash or .docx is taken as a path. Cannot be
                       combined with --preset.
  -l, --list-presets   show the available presets and exit
      --set P.KEY=VAL  change a value in presets.ini and exit
  -h, --help           show this help and exit

examples:
  build.sh                                   resumes/resume.md -> resumes/out/resume.docx
  build.sh resumes/acme.md                   -> resumes/out/acme.docx
  build.sh resumes/acme.md resumes/out/Acme_Corp.docx
  build.sh --preset clean resumes/resume.md
  build.sh --set clean.bullet_right=1800
  build.sh --template mine.docx resumes/resume.md

Your resumes live in resumes/, which is gitignored in full, so nothing you
write there can reach the repository. Design values live in presets.ini;
README.md explains what each one controls.
USAGE
}

PRESET=""
TEMPLATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)  usage; exit 0 ;;
    -l|--list-presets)
                exec python3 tools/make_reference.py --list-presets ;;
    --set)      [ $# -ge 2 ] || { echo "--set needs PRESET.KEY=VALUE" >&2; exit 1; }
                exec python3 tools/make_reference.py --set "$2" ;;
    --set=*)    exec python3 tools/make_reference.py --set "${1#*=}" ;;
    -t|--template)
                [ $# -ge 2 ] || { echo "--template needs a name or path" >&2; exit 1; }
                TEMPLATE="$2"; shift 2 ;;
    --template=*) TEMPLATE="${1#*=}"; shift ;;
    -p|--preset)
                [ $# -ge 2 ] || { echo "--preset needs a name" >&2; exit 1; }
                PRESET="$2"; shift 2 ;;
    --preset=*) PRESET="${1#*=}"; shift ;;
    -p=*)       PRESET="${1#*=}"; shift ;;
    --)         shift; break ;;
    -*)         echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
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

mkdir -p "$OUT_DIR"

if [ -n "$TEMPLATE" ]; then
  # Your own design. Presets shape the document this script generates, and a
  # template replaces that step entirely, so combining them is contradictory
  # rather than merely redundant -- say so instead of ignoring one silently.
  if [ -n "$PRESET" ]; then
    echo "--template and --preset cannot be combined" >&2
    echo "  a template carries its own design; presets only shape a generated one" >&2
    exit 1
  fi
  case "$TEMPLATE" in
    */*|*.docx) REF="$TEMPLATE" ;;
    *)          REF="templates/$TEMPLATE.docx" ;;
  esac
  [ -f "$REF" ] || { echo "no such template: $REF" >&2; exit 1; }
  # Missing styles are not fatal to Pandoc, which is exactly why they are worth
  # naming: the output degrades in silence otherwise.
  python3 tools/make_reference.py --check-template "$REF" >&2 \
    || echo "  building anyway -- --check-template alone exits nonzero" >&2
else
  mkdir -p "$BUILD_DIR"
  if [ -n "$PRESET" ]; then REF="$BUILD_DIR/reference-$PRESET.docx"; else REF="$BUILD_DIR/reference.docx"; fi
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
fi

pandoc "$SRC" \
  --reference-doc="$REF" \
  --lua-filter=tools/rightalign.lua \
  -o "$OUT"

echo "wrote $OUT${PRESET:+ [preset: $PRESET]}${TEMPLATE:+ [template: $REF]}"

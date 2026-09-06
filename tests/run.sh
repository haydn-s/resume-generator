#!/usr/bin/env bash
#
# Test suite for the resume pipeline. Runs locally and in CI:
#
#   tests/run.sh                 everything
#   tests/run.sh privacy build   only the named groups
#
# Groups: privacy build lint docs
#
# Builds run inside a throwaway copy of the working tree, so the suite never
# touches your own resume.md or reference.docx. Checks whose tool is missing
# are skipped, not failed, so a local run without shellcheck still works.
#
set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0; FAIL=0; SKIP=0
if [ -z "${NO_COLOR:-}" ] && { [ -t 1 ] || [ -n "${CI:-}" ]; }; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; Z=$'\033[0m'
else
  G=""; R=""; Y=""; B=""; Z=""
fi
group() { printf '\n%s%s%s\n' "$B" "$1" "$Z"; }
pass()  { printf '  %sPASS%s  %s\n' "$G" "$Z" "$1"; PASS=$((PASS + 1)); }
skip()  { printf '  %sSKIP%s  %s (%s)\n' "$Y" "$Z" "$1" "${2:-unavailable}"; SKIP=$((SKIP + 1)); }
fail()  {
  printf '  %sFAIL%s  %s\n' "$R" "$Z" "$1"; FAIL=$((FAIL + 1))
  if [ $# -gt 1 ] && [ -n "$2" ]; then printf '%s\n' "$2" | sed 's/^/          /'; fi
  return 0
}

WANT="${*:-privacy build lint docs}"
want() { printf '%s' "$WANT" | grep -qw "$1"; }

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
git ls-files --cached --others --exclude-standard -z | while IFS= read -r -d '' f; do
  mkdir -p "$SANDBOX/$(dirname "$f")" && cp -p "$f" "$SANDBOX/$f"
done
sb() { ( cd "$SANDBOX" && "$@" ); }

# Every .md in the tree except the README, so a local run also lints the
# personal resumes that CI never sees.
md_files() { find . -name '*.md' -not -path './.git/*' -not -name 'README.md' | sort; }

# ---------------------------------------------------------------- privacy
if want privacy; then
  group "Privacy"

  leaked=$(git ls-files \
    | grep -Ei '(resume.*\.md$|\.docx$|\.pdf$)' \
    | grep -v '\.template\.md$' \
    | grep -vx 'Resume_Template\.docx' || true)
  if [ -z "$leaked" ]; then pass "no personal content is tracked"
  else fail "personal content is tracked" "$leaked"; fi

  missed=""
  for f in resume.md master_resume.md Haydn_Resume.md resume-acme.md \
           My_Resume.docx Stucker_Resume.docx export.pdf; do
    git check-ignore -q "$f" || missed="$missed $f"
  done
  if [ -z "$missed" ]; then pass "gitignore covers personal filenames"
  else fail "gitignore does not cover:" "$missed"; fi

  over=""
  for f in resume.template.md Resume_Template.docx README.md presets.ini build.sh; do
    git check-ignore -q "$f" && over="$over $f"
  done
  if [ -z "$over" ]; then pass "gitignore does not over-match project files"
  else fail "gitignore wrongly ignores:" "$over"; fi
fi

# ------------------------------------------------------------------ build
if want build; then
  group "Build"
  FX=tests/fixtures/all-features.md
  if ! command -v pandoc >/dev/null; then
    skip "all build checks" "pandoc not installed"
  else
    if sb sh -c 'cp resume.template.md resume.md && ./build.sh' >/dev/null 2>&1; then
      pass "fresh-clone flow (cp template, ./build.sh)"
    else
      fail "fresh-clone flow failed"
    fi

    out=$(sb sh -c 'rm -f resume.md; ./build.sh' 2>&1); rc=$?
    if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'resume.template.md'; then
      pass "missing resume.md errors and points at the template"
    else
      fail "missing resume.md did not error helpfully" "$out"
    fi

    presets=$(python3 -c "
import configparser
c = configparser.ConfigParser(inline_comment_prefixes=('#', ';'))
c.read('presets.ini')
print('DEFAULT ' + ' '.join(c.sections()))")
    bad=""
    for p in $presets; do
      sb ./build.sh --preset "$p" "$FX" "out-$p.docx" >/dev/null 2>&1 || bad="$bad $p"
    done
    if [ -z "$bad" ]; then pass "every preset builds ($presets)"
    else fail "presets failed to build:" "$bad"; fi

    if sb ./build.sh --preset no-such-preset "$FX" o.docx >/dev/null 2>&1; then
      fail "an unknown preset was silently accepted"
    else
      pass "unknown preset exits nonzero"
    fi

    got=$(python3 tests/lib/docx.py styles "$SANDBOX/out-DEFAULT.docx" | tr '\n' ' ')
    missing=""
    for s in Name Tagline Contact Heading1 Heading2 FirstParagraph BodyText Compact; do
      printf '%s' "$got" | grep -qw "$s" || missing="$missing $s"
    done
    if [ -z "$missing" ]; then pass "all 8 paragraph styles applied"
    else fail "styles absent from output:" "$missing"; fi

    src=$(grep -o '@@' "$FX" | wc -l | tr -d ' ')
    tabs=$(python3 tests/lib/docx.py tabs "$SANDBOX/out-DEFAULT.docx")
    left=$(python3 tests/lib/docx.py literal-at "$SANDBOX/out-DEFAULT.docx")
    if [ "$src" = "$tabs" ] && [ "$left" = "0" ]; then
      pass "@@ conversion ($src markers, $tabs tabs, 0 literal left)"
    else
      fail "@@ conversion mismatch" "source=$src tabs=$tabs literal_remaining=$left"
    fi

    a=$(python3 tests/lib/docx.py style-attr "$SANDBOX/out-DEFAULT.docx" Compact 'w:right')
    b=$(python3 tests/lib/docx.py style-attr "$SANDBOX/out-clean.docx" Compact 'w:right')
    if [ -n "$a" ] && [ "$a" != "$b" ]; then
      pass "presets reach the output (DEFAULT w:right=$a, clean=$b)"
    else
      fail "preset made no difference to the output" "DEFAULT=$a clean=$b"
    fi
  fi
fi

# ------------------------------------------------------------------- lint
if want lint; then
  group "Lint"

  dangle=""
  while IFS= read -r f; do
    hit=$(awk -v F="$f" 'prev ~ /\\$/ && $0 == "" { print F ":" NR - 1 } { prev = $0 }' "$f")
    [ -n "$hit" ] && dangle="$dangle$hit"$'\n'
  done < <(md_files)
  if [ -z "$dangle" ]; then pass "no dangling hard break before a blank line"
  else fail "trailing '\\' produces a stray empty line:" "$dangle"; fi

  dated=""
  while IFS= read -r f; do
    hit=$(grep -n '^- .*@@' "$f" | sed "s|^|$f:|")
    [ -n "$hit" ] && dated="$dated$hit"$'\n'
  done < <(md_files)
  if [ -z "$dated" ]; then pass "no bullet carries an @@ date"
  else fail "dated bullets break alignment when bullet_right is set:" "$dated"; fi

  if bash -n build.sh 2>/dev/null && bash -n tests/run.sh 2>/dev/null; then
    pass "shell scripts parse"
  else
    fail "shell syntax error" "$(bash -n build.sh 2>&1; bash -n tests/run.sh 2>&1)"
  fi

  if command -v shellcheck >/dev/null; then
    sc=$(shellcheck -S warning build.sh tests/run.sh 2>&1)
    if [ -z "$sc" ]; then pass "shellcheck clean"; else fail "shellcheck findings" "$sc"; fi
  else
    skip "shellcheck" "not installed"
  fi

  pyerr=$(python3 -c "
import ast
bad = []
for f in ['make_reference.py', 'tests/lib/docx.py']:
    try:
        ast.parse(open(f).read(), f)
    except SyntaxError as e:
        bad.append('%s:%s %s' % (f, e.lineno, e.msg))
print('\n'.join(bad))")
  if [ -z "$pyerr" ]; then pass "python parses"; else fail "python syntax error" "$pyerr"; fi

  if command -v ruff >/dev/null; then
    rf=$(ruff check make_reference.py tests/lib/docx.py 2>&1)
    if [ $? -eq 0 ]; then pass "ruff clean"; else fail "ruff findings" "$rf"; fi
  else
    skip "ruff" "not installed"
  fi
fi

# ------------------------------------------------------------------- docs
if want docs; then
  group "Docs"

  fences=$(grep -c '^```' README.md)
  if [ $((fences % 2)) -eq 0 ]; then pass "README code fences balanced ($fences)"
  else fail "README has an unclosed code fence ($fences)"; fi

  if command -v pandoc >/dev/null; then
    if pandoc README.md -t html -o /dev/null 2>/dev/null; then pass "README parses"
    else fail "README does not parse"; fi
  else
    skip "README parse" "pandoc not installed"
  fi

  ghost=""
  for p in $(grep -oE '\-\-preset[= ][A-Za-z0-9_-]+' README.md | sed 's/.*[= ]//' | sort -u); do
    [ "$p" = "NAME" ] && continue
    grep -q "^\[$p\]" presets.ini || ghost="$ghost $p"
  done
  if [ -z "$ghost" ]; then pass "every preset named in the README exists"
  else fail "README documents presets that are not in presets.ini:" "$ghost"; fi
fi

printf '\n%s%d passed, %d failed, %d skipped%s\n' "$B" "$PASS" "$FAIL" "$SKIP" "$Z"
[ "$FAIL" -eq 0 ]

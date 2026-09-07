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
cd "$(dirname "$0")/.." || exit 1

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

# Resume source markdown only. Project documentation is excluded: these checks
# are about how an entry is written, and prose that *describes* the rules would
# otherwise trip them. Everything else in the tree is included, so a local run
# also lints the personal resumes CI never sees.
md_files() {
  find . -name '*.md' -not -path './.git/*' -not -path './node_modules/*' \
    -not -name 'README.md' -not -name 'CONTRIBUTING.md' | sort
}

# ---------------------------------------------------------------- privacy
if want privacy; then
  group "Privacy"

  leaked=$(git ls-files | grep -E '^(resumes|build)/' | grep -v '/\.gitkeep$' || true)
  if [ -z "$leaked" ]; then pass "nothing tracked under resumes/ or build/"
  else fail "personal or generated content is tracked" "$leaked"; fi

  # The point of the directory rule: these are covered whatever they are
  # called, including names no filename pattern would have anticipated.
  missed=""
  for f in resumes/resume.md resumes/master_resume.md resumes/cover-letter.md \
           resumes/notes.txt resumes/anything.pdf resumes/out/Any_Name.docx \
           build/reference.docx; do
    git check-ignore -q "$f" || missed="$missed $f"
  done
  if [ -z "$missed" ]; then pass "resumes/ and build/ are ignored wholesale"
  else fail "gitignore does not cover:" "$missed"; fi

  over=""
  for f in templates/resume.template.md templates/Resume_Template.docx \
           resumes/.gitkeep resumes/out/.gitkeep \
           README.md presets.ini build.sh tools/make_reference.py; do
    git check-ignore -q "$f" && over="$over $f"
  done
  if [ -z "$over" ]; then pass "gitignore does not over-match project files"
  else fail "gitignore wrongly ignores:" "$over"; fi
fi

# ------------------------------------------------------------------ build
if want build; then
  group "Build"
  FX=tests/fixtures/all-features.md

  # The CLI surface needs no pandoc. --help in particular has to work on a
  # machine that has not installed it yet, which is exactly when it is read.
  if out=$(sb ./build.sh --help 2>&1) && printf '%s' "$out" | grep -q '^usage: build.sh'; then
    pass "--help prints usage and exits 0"
  else
    fail "--help did not print usage" "$out"
  fi

  if sb ./build.sh -h >/dev/null 2>&1; then pass "-h is accepted"
  else fail "-h was rejected"; fi

  if sb ./build.sh --no-such-flag >/dev/null 2>&1; then
    fail "an unknown option was silently accepted"
  else
    pass "unknown option exits nonzero"
  fi

  if ! command -v pandoc >/dev/null; then
    skip "remaining build checks" "pandoc not installed"
  else
    if sb sh -c 'cp templates/resume.template.md resumes/resume.md && ./build.sh' >/dev/null 2>&1; then
      pass "fresh-clone flow (cp template, ./build.sh)"
    else
      fail "fresh-clone flow failed"
    fi

    out=$(sb sh -c 'rm -f resumes/resume.md; ./build.sh' 2>&1); rc=$?
    if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'templates/resume.template.md'; then
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
      sb ./build.sh --preset "$p" "$FX" "resumes/out/out-$p.docx" >/dev/null 2>&1 || bad="$bad $p"
    done
    if [ -z "$bad" ]; then pass "every preset builds ($presets)"
    else fail "presets failed to build:" "$bad"; fi

    listed=$(sb ./build.sh --list-presets 2>&1)
    absent=""
    for p in $presets; do
      printf '%s' "$listed" | grep -qw "$p" || absent="$absent $p"
    done
    if [ -z "$absent" ]; then pass "--list-presets shows every preset in presets.ini"
    else fail "--list-presets omits:" "$absent"; fi

    sb ./build.sh -p clean "$FX" resumes/out/short.docx >/dev/null 2>&1
    sb ./build.sh --preset clean "$FX" resumes/out/long.docx >/dev/null 2>&1
    a=$(python3 tests/lib/docx.py style-attr "$SANDBOX/resumes/out/short.docx" Compact 'w:right')
    b=$(python3 tests/lib/docx.py style-attr "$SANDBOX/resumes/out/long.docx" Compact 'w:right')
    if [ -n "$a" ] && [ "$a" = "$b" ]; then pass "-p and --preset agree (w:right=$a)"
    else fail "-p and --preset disagree" "-p=$a --preset=$b"; fi

    if sb ./build.sh --preset no-such-preset "$FX" resumes/out/o.docx >/dev/null 2>&1; then
      fail "an unknown preset was silently accepted"
    else
      pass "unknown preset exits nonzero"
    fi

    got=$(python3 tests/lib/docx.py styles "$SANDBOX/resumes/out/out-DEFAULT.docx" | tr '\n' ' ')
    missing=""
    for s in Name Tagline Contact Heading1 Heading2 FirstParagraph BodyText Compact; do
      printf '%s' "$got" | grep -qw "$s" || missing="$missing $s"
    done
    if [ -z "$missing" ]; then pass "all 8 paragraph styles applied"
    else fail "styles absent from output:" "$missing"; fi

    src=$(grep -o '@@' "$FX" | wc -l | tr -d ' ')
    tabs=$(python3 tests/lib/docx.py tabs "$SANDBOX/resumes/out/out-DEFAULT.docx")
    left=$(python3 tests/lib/docx.py literal-at "$SANDBOX/resumes/out/out-DEFAULT.docx")
    if [ "$src" = "$tabs" ] && [ "$left" = "0" ]; then
      pass "@@ conversion ($src markers, $tabs tabs, 0 literal left)"
    else
      fail "@@ conversion mismatch" "source=$src tabs=$tabs literal_remaining=$left"
    fi

    a=$(python3 tests/lib/docx.py style-attr "$SANDBOX/resumes/out/out-DEFAULT.docx" Compact 'w:right')
    b=$(python3 tests/lib/docx.py style-attr "$SANDBOX/resumes/out/out-clean.docx" Compact 'w:right')
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

  if bash -n build.sh 2>/dev/null && bash -n tests/run.sh 2>/dev/null \
     && bash -n tools/install-pandoc.sh 2>/dev/null; then
    pass "shell scripts parse"
  else
    fail "shell syntax error" "$(bash -n build.sh 2>&1; bash -n tests/run.sh 2>&1)"
  fi

  if command -v shellcheck >/dev/null; then
    sc=$(shellcheck -S warning build.sh tests/run.sh tools/install-pandoc.sh 2>&1)
    if [ -z "$sc" ]; then pass "shellcheck clean"; else fail "shellcheck findings" "$sc"; fi
  else
    skip "shellcheck" "not installed"
  fi

  pyerr=$(python3 -c "
import ast
bad = []
for f in ['tools/make_reference.py', 'tests/lib/docx.py']:
    try:
        ast.parse(open(f).read(), f)
    except SyntaxError as e:
        bad.append('%s:%s %s' % (f, e.lineno, e.msg))
print('\n'.join(bad))")
  if [ -z "$pyerr" ]; then pass "python parses"; else fail "python syntax error" "$pyerr"; fi

  # commitlint needs Node, which the rest of this project does not. Skipped
  # when absent so a local run stays dependency-free; CI always runs it.
  cl=""
  command -v commitlint >/dev/null && cl=commitlint
  [ -x node_modules/.bin/commitlint ] && cl=node_modules/.bin/commitlint
  if [ -n "$cl" ]; then
    base=$(git merge-base origin/main HEAD 2>/dev/null || echo "")
    if [ -z "$base" ]; then
      skip "commitlint" "no origin/main to compare against"
    elif out=$("$cl" --from "$base" --to HEAD 2>&1); then
      pass "commit messages are conventional"
    else
      fail "commitlint findings" "$out"
    fi
  else
    skip "commitlint" "not installed; npx @commitlint/cli"
  fi

  if command -v ruff >/dev/null; then
    rf=$(ruff check tools/ tests/ 2>&1)
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

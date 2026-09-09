# Resumé Generator Pipeline

Markdown in, formatted DOCX out. Content and design stay in separate files, so
you can rewrite one without touching the other.

Needs Pandoc — see [Installing Pandoc](#installing-pandoc) if you don't have it.
Then start from the template:

```bash
cp templates/resume.template.md resumes/resume.md
./build.sh
```

That reads `resumes/resume.md` and writes `resumes/out/resume.docx`.

```bash
./build.sh --help          # every option, with examples
./build.sh --list-presets  # the presets and what each one changes
```

Everything of yours lives in `resumes/`, which is gitignored in full — content
and output both. The guarantee is structural rather than a filename pattern, so
a `cover-letter.md` or a `haydn_cv.pdf` dropped in there is covered too.

## Files

| Path | What it is |
|---|---|
| `resumes/` | **Yours.** Source markdown and built documents. Gitignored in full. |
| `resumes/out/` | Where built documents land. |
| `templates/resume.template.md` | The starting point. Copy it into `resumes/`. |
| `templates/Resume_Template.docx` | The original Word design, kept as a reference. Not an input — see below. |
| `presets.ini` | **The design values.** Fonts, sizes, spacing. Pick one with `--preset`. |
| `build.sh` | The one command you run. |
| `tools/make_reference.py` | Turns a preset into the style carrier. Holds the style structure. |
| `tools/rightalign.lua` | Turns the `@@` marker into a right-aligned tab. |
| `tools/install-pandoc.sh` | Installs a given Pandoc release. Used by CI. |
| `build/` | Generated style carriers. Disposable. |
| `tests/` | The test suite. |

Anything under `build/` and `resumes/out/` can be deleted at any time;
`build.sh` rebuilds it.

### `Resume_Template.docx` is a specimen, not an input

It is the hand-made Word document this pipeline was built to reproduce, and
`[DEFAULT]` in `presets.ini` is copied from it — Calibri at 10.5pt, half-inch
margins, US Letter. It is kept so the target is still inspectable.

Nothing reads it at build time. Pandoc is handed `build/reference.docx`, which
`tools/make_reference.py` generates from Pandoc's *own* default reference
document, restyled from the preset you chose. The Word file is not part of that
chain.

The consequence is worth knowing before you open it: **editing it changes
nothing.** Bump its body font to 11pt in Word, save, rebuild, and every resume
still comes out at 10.5pt. The numbers live in `presets.ini`; this file is only
where they were first copied from. It also predates the pipeline's own styles —
`Name`, `Tagline`, `Contact` and `Compact` exist only in
`tools/make_reference.py`, never in the Word original.

## Writing your resume

**Section headings** are `#`. They pick up the Heading 1 style — bold caps on a
full-width rule.

**Right-aligned dates** use `@@`. Everything after it goes flush to the right
margin:

```markdown
**Software Development Intern** --- Acme Corp, Springfield, IL @@ May 2026 -- Present
```

**Multi-line entries** use a backslash at the end of each line. This keeps the
lines in one paragraph so they stay tight together:

```markdown
**State University**, Springfield, IL @@ Expected August 2027\
M.S. in Computer Science | Machine Learning
```

A blank line instead starts a new paragraph, which adds the gap between entries.

**Bullets** are `-`.

**Comments** are `<!-- ... -->` and never reach the DOCX. Use them for notes to
yourself about what belongs in a section.

**The header block** uses fenced divs, which map to named paragraph styles:

```markdown
::: {custom-style="Name"}
Jane Q. Public
:::
```

`Name`, `Tagline`, and `Contact` are defined in `tools/make_reference.py`.

**Em dashes** are `---` and en dashes are `--`. Pandoc converts them.

### LaTeX math renders, but keep it out of your bullets

Pandoc reads `$...$` and `$$...$$` as math and writes real Word equation
objects, so this needs no configuration and already works:

```markdown
- Cut median latency by reducing the sort to $O(n \log n)$.
```

It is still usually the wrong call. Word keeps an equation's text in its own
`m:t` elements instead of the `w:t` runs everything else uses, so any tool that
reads a DOCX by walking `w:t` — the common approach, and what a lot of
applicant tracking systems do — gets the line back with a hole in it:

```
Cut median latency by reducing the sort to  .
```

The formatting you gain is small, and the text you lose is the quantified part
a screener came for. Write `O(n log n)` as plain text instead. Real math is
worth it only in a document a human will read whole, never in a bullet you need
parsed.

Two related notes:

- **Raw LaTeX commands are dropped in silence.** `\textbf{...}`, `\LaTeX{}` and
  environments parse as raw TeX, which the DOCX writer discards without a
  warning. Only the math delimiters survive the trip.
- **Dollar amounts are safe.** Pandoc opens math only on a `$` with no space
  after it, and closes only on a `$` with no space before it and no digit after
  it, so `$50k-$100k`, `$1.2M/$3.4M`, `$1M to $5M` and `$75,000` all come
  through as written. The one shape that misfires is a letter-led pair like
  `$USD-$CAD`, which parses as math; escape it as `\$USD-\$CAD`.

## Tailoring for a specific application

Copy the file and cut:

```bash
cp resumes/resume.md resumes/acme.md
# edit resumes/acme.md down to what Acme cares about
./build.sh resumes/acme.md resumes/out/Acme_Corp.docx
```

Every variant renders with identical formatting, because the formatting isn't
in any of them.

## Changing the design

The design splits in two. Numbers — fonts, sizes, page geometry, spacing —
live in `presets.ini`, so you can keep several looks side by side and choose
between them at build time. Structure lives in `tools/make_reference.py`, where
`STYLES` maps each style to its paragraph and run properties in raw OOXML.
Change either, run `./build.sh`, and every resume you generate from then on
picks it up.

Two things are load-bearing and worth knowing before you edit:

- The right tab stop in `Normal` is set to `PAGE_W - 2 * MARGIN`. If you change
  the margins, the tab follows automatically — but only because it's computed.
  Don't hardcode it.
- Pandoc only emits the style IDs listed in `STYLES`. Adding a style to
  `tools/make_reference.py` does nothing unless something in your resume references
  it, via a `#` heading level or a `custom-style` div.

### Presets

Numeric design values live in `presets.ini` rather than in code. `[DEFAULT]` is
the base design; every other section inherits from it and overrides only what it
changes, so a preset is usually two or three lines:

```ini
[DEFAULT]
body_font    = Calibri
display_font = Arial
body_size    = 21       # half-points, so 21 = 10.5pt
page_width   = 12240    # US Letter
page_height  = 15840
margin       = 720      # 0.5in
spacing      = 1.0      # multiplier on every paragraph before/after gap
line         = 252      # line height in 240ths; 240 = single, 252 = 1.05
bullet_right = 1440     # how far bullet text stops short of the right margin

[roomy]
spacing = 1.75
line    = 276
```

Pick one at build time:

```bash
./build.sh --preset roomy resumes/resume.md
./build.sh                                   # [DEFAULT]
```

Four ship with the repo: `clean` (bullets well clear of the date column),
`roomy` (looser, runs longer), `compact` (tighter), and `onepage` (smaller type
and narrower margins as well). Add your own by copying a section and renaming
it — any `[DEFAULT]` key can be overridden.

`./build.sh --list-presets` prints them along with the keys each one overrides,
so you don't have to open the file to remember what `compact` does:

```
presets in presets.ini:

  DEFAULT  the baseline design
  clean    bullet_right = 2160
  roomy    spacing = 1.75, line = 276
  compact  spacing = 0.8, line = 240, bullet_right = 720
  onepage  body_size = 20, margin = 576, spacing = 0.7, line = 240, bullet_right = 720
```

#### Changing a value from the command line

```bash
./build.sh --set clean.bullet_right=1800
```

That writes straight to `presets.ini`. The key has to exist in `[DEFAULT]` and
the value has to parse as the same type, so a typo fails immediately instead of
at build time. A key the preset merely inherits is added to it.

Comments survive: the file is edited line by line rather than through
`configparser.write()`, which discards every comment — and `presets.ini` is
mostly comments explaining what the numbers mean. What the command can't do is
keep a comment *true*. Change `bullet_right` and the `# 1.5in` beside it still
says 1.5in, so it tells you which comment it preserved and leaves the judgement
to you.

Each preset caches its own `build/reference-<preset>.docx`, so switching back and
forth doesn't rebuild every time. A carrier is regenerated when it is older than
either `tools/make_reference.py` or `presets.ini`, so editing a preset takes effect on
the next build.

#### What the values mean

Spacing is in DXA — twentieths of a point — so 20 DXA = 1pt, and 1440 = 1 inch.
`spacing` is a plain multiplier on every before/after gap; `line` is absolute,
in 240ths of a line.

| Key | Controls | Default |
|---|---|---|
| `spacing` | Multiplier on every paragraph gap | 1.0 |
| `line` | Line height inside a paragraph | 252 = 1.05x |
| `bullet_right` | How far bullets stop short of the right margin | 1440 = 1in |
| `body_size` | Body type size, in half-points | 21 = 10.5pt |
| `margin` | Page margin, all four sides | 720 = 0.5in |

Scaling zero gives zero, so `spacing` only widens gaps that already exist.
`FirstParagraph` and `Contact` never move however high you push it — by design,
since a paragraph under a heading takes its air from the heading's own `after`.

Structure stays in code. `STYLES` decides which styles are bold and which carry
a rule; a preset cannot reach it. Presets change proportions, not anatomy.

#### One-off overrides

Any key can be overridden for a single run by an environment variable of the
same name in caps. Precedence is environment variable, then preset, then
`[DEFAULT]`:

```bash
SPACING=2.0 ./build.sh --preset roomy
BULLET_RIGHT=1800 python3 tools/make_reference.py build/reference-test.docx
```

One trap: `build.sh` regenerates the style carrier only when it is missing or
older than `tools/make_reference.py` or `presets.ini`. It knows nothing about
environment variables, so with a current carrier `SPACING=2.0 ./build.sh` is
silently a no-op — no error, just the old spacing. Delete the carrier first:

```bash
rm build/reference.docx && SPACING=2.0 ./build.sh
```

That timestamp comparison is whole-second on macOS's bash 3.2, so an edit and a
build inside the same second can miss each other — another reason `rm` is the
reliable move.

## Other output formats

The Lua filter degrades gracefully — `@@` becomes a plain space outside DOCX:

```bash
pandoc resumes/resume.md --lua-filter=tools/rightalign.lua --strip-comments \
  -t plain -o resumes/out/resume.txt
```

`-t plain` is load-bearing. Pandoc maps a bare `.txt` extension to the
*markdown* writer, so leaving it off gets you `:::` fences and escaped brackets
instead of readable text.

`--strip-comments` is only needed outside DOCX. The DOCX writer drops HTML
comments on its own; the plain-text writer does not.

For PDF, generate the DOCX first and export from Word, so the PDF matches the
DOCX exactly.

## Installing Pandoc

Pandoc does the actual conversion, and `tools/make_reference.py` needs Python 3.
macOS and most Linux distributions ship Python 3 already, so Pandoc is usually
the only thing to install.

**macOS**

```bash
brew install pandoc
```

Without Homebrew, download the `.pkg` from
[the releases page](https://github.com/jgm/pandoc/releases/latest) and
double-click it. That installs Pandoc alone, no package manager required.

**Debian / Ubuntu**

```bash
sudo apt install pandoc
```

**Fedora / RHEL**

```bash
sudo dnf install pandoc
```

**Windows**

```
winget install --id JohnMacFarlane.Pandoc
```

### Check the version

```bash
pandoc --version
```

2.17 or newer is required — that's when the Lua `Inlines` filter that
`tools/rightalign.lua` depends on was added. Built and tested against 3.1.3.

Distribution packages lag behind, so `apt` and `dnf` on an older release can
land you below 2.17. If they do, uninstall and use the `.deb` or `.rpm` from
the releases page instead.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the commit-message convention
(Conventional Commits, enforced by commitlint in CI) and what to run before
opening a pull request.

## Tests

```bash
tests/run.sh                 # everything
tests/run.sh privacy lint    # only the named groups
```

Groups are `privacy`, `build`, `lint` and `docs`. Builds run inside a throwaway
copy of the working tree, so the suite never touches your own `resumes/`
or `build/`. A check whose tool is missing is skipped rather than failed,
so a local run without `shellcheck` still works.

| Group | What it checks |
|---|---|
| `privacy` | No personal content is tracked; `.gitignore` covers the filenames that matter and doesn't over-match project files. |
| `build` | The fresh-clone flow works, a missing source errors helpfully, every preset builds, an unknown preset exits nonzero, all eight paragraph styles reach the DOCX, every `@@` becomes a tab, and a preset visibly changes the output. |
| `lint` | No dangling `\` before a blank line, no bullet carrying an `@@` date, shell and Python parse, commit messages are conventional, plus shellcheck, ruff and commitlint when installed. Ruff's rules are pinned in `ruff.toml`, targeting py39 so it never suggests syntax the stock-macOS interpreter can't run. |
| `docs` | README fences balance and it parses; every preset the README names exists in `presets.ini`. |

Two of those encode decisions rather than mechanics, and are worth knowing
before you "fix" them:

- **Bullets must not carry `@@` dates.** A bullet's right indent moves its tab
  stop inward, so a date on a bullet stops short of every other date on the
  page. Keeping dates off bullets is what makes `bullet_right` safe to tune.
- **The `\(555)` escape in the fixture is load-bearing.** Pandoc reads a
  leading `(555)` as ordered-list syntax, swallows the line into a list, and
  silently drops the paragraph style. Exit code 0, no warning.

CI runs the same script on every push and pull request, in
`.github/workflows/ci.yml`. It builds against Pandoc 2.17, 3.1.3 and latest on
Linux, and 3.1.3 and latest on macOS — 2.17 ships no macOS build. It also runs
the build group under Python 3.9 and 3.13; the 3.9 leg exists because stock
macOS ships it, and it is the reason presets are INI rather than TOML.


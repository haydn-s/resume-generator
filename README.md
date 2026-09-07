# Resumé Generator Pipeline

Markdown in, formatted DOCX out. Content and design stay in separate files, so
you can rewrite one without touching the other.

Needs Pandoc — see [Installing Pandoc](#installing-pandoc) if you don't have it.
Then start from the template:

```bash
cp resume.template.md resume.md
./build.sh
```

That reads `resume.md` and writes `resume.docx`.

`resume.md` is gitignored, along with anything else matching `*resume*.md` —
your content stays yours. Files ending in `.template.md` are the exception: they
hold placeholders, so they're tracked and a fresh clone always has one to copy.

## Files

| File | What it is |
|---|---|
| `resume.template.md` | The starting point. Copy it to `resume.md`. Tracked. |
| `resume.md` | **Your content.** The only file you normally edit. Gitignored. |
| `reference.docx` | The design. Pandoc reads its styles and throws away its text. |
| `presets.ini` | **The design values.** Fonts, sizes, spacing. Pick one with `--preset`. |
| `make_reference.py` | Turns a preset into `reference.docx`. Holds the style structure. |
| `rightalign.lua` | Turns the `@@` marker into a right-aligned tab. |
| `build.sh` | Runs Pandoc with the right flags. |

Generated files (`reference.docx`, `resume.docx`) can be deleted at any time;
`build.sh` rebuilds them.

## Writing `resume.md`

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

`Name`, `Tagline`, and `Contact` are defined in `make_reference.py`.

**Em dashes** are `---` and en dashes are `--`. Pandoc converts them.

## Tailoring for a specific application

Copy the file and cut:

```bash
cp resume.md resume-acme.md
# edit resume-acme.md down to what Acme cares about
./build.sh resume-acme.md Resume_Acme.docx
```

Every variant renders with identical formatting, because the formatting isn't
in any of them.

## Changing the design

The design splits in two. Numbers — fonts, sizes, page geometry, spacing —
live in `presets.ini`, so you can keep several looks side by side and choose
between them at build time. Structure lives in `make_reference.py`, where
`STYLES` maps each style to its paragraph and run properties in raw OOXML.
Change either, run `./build.sh`, and every resume you generate from then on
picks it up.

Two things are load-bearing and worth knowing before you edit:

- The right tab stop in `Normal` is set to `PAGE_W - 2 * MARGIN`. If you change
  the margins, the tab follows automatically — but only because it's computed.
  Don't hardcode it.
- Pandoc only emits the style IDs listed in `STYLES`. Adding a style to
  `make_reference.py` does nothing unless something in `resume.md` references
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
./build.sh --preset roomy resume.md Resume_Roomy.docx
./build.sh                                   # [DEFAULT]
```

Three ship with the repo: `roomy` (looser, runs longer), `compact` (tighter),
and `onepage` (smaller type and narrower margins as well). Add your own by
copying a section and renaming it — any `[DEFAULT]` key can be overridden.

Each preset caches its own `reference-<preset>.docx`, so switching back and
forth doesn't rebuild every time. A carrier is regenerated when it is older than
either `make_reference.py` or `presets.ini`, so editing a preset takes effect on
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
BULLET_RIGHT=1800 python3 make_reference.py reference-test.docx
```

One trap: `build.sh` regenerates the style carrier only when it is missing or
older than `make_reference.py` or `presets.ini`. It knows nothing about
environment variables, so with a current carrier `SPACING=2.0 ./build.sh` is
silently a no-op — no error, just the old spacing. Delete the carrier first:

```bash
rm reference.docx && SPACING=2.0 ./build.sh
```

That timestamp comparison is whole-second on macOS's bash 3.2, so an edit and a
build inside the same second can miss each other — another reason `rm` is the
reliable move.

## Other output formats

The Lua filter degrades gracefully — `@@` becomes a plain space outside DOCX:

```bash
pandoc resume.md --lua-filter=rightalign.lua --strip-comments \
  -t plain -o resume.txt
```

`-t plain` is load-bearing. Pandoc maps a bare `.txt` extension to the
*markdown* writer, so leaving it off gets you `:::` fences and escaped brackets
instead of readable text.

`--strip-comments` is only needed outside DOCX. The DOCX writer drops HTML
comments on its own; the plain-text writer does not.

For PDF, generate the DOCX first and export from Word, so the PDF matches the
DOCX exactly.

## Installing Pandoc

Pandoc does the actual conversion, and `make_reference.py` needs Python 3.
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
`rightalign.lua` depends on was added. Built and tested against 3.1.3.

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
copy of the working tree, so the suite never touches your own `resume.md` or
`reference.docx`. A check whose tool is missing is skipped rather than failed,
so a local run without `shellcheck` still works.

| Group | What it checks |
|---|---|
| `privacy` | No personal content is tracked; `.gitignore` covers the filenames that matter and doesn't over-match project files. |
| `build` | The fresh-clone flow works, a missing `resume.md` errors helpfully, every preset builds, an unknown preset exits nonzero, all eight paragraph styles reach the DOCX, every `@@` becomes a tab, and a preset visibly changes the output. |
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


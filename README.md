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
| `make_reference.py` | Regenerates `reference.docx`. Edit this to change the look. |
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

Everything visual lives in `make_reference.py`. The knobs at the top cover
fonts, body size, page size, and margins:

```python
BODY_FONT = "Calibri"
DISPLAY_FONT = "Arial"
BODY_SIZE = 21          # half-points, so 21 = 10.5pt
MARGIN = 720            # DXA, 1440 = 1 inch
```

Below that, `STYLES` maps each style to its paragraph and run properties in raw
OOXML. Change one, run `./build.sh`, and every resume you generate from then on
picks it up.

Two things are load-bearing and worth knowing before you edit:

- The right tab stop in `Normal` is set to `PAGE_W - 2 * MARGIN`. If you change
  the margins, the tab follows automatically — but only because it's computed.
  Don't hardcode it.
- Pandoc only emits the style IDs listed in `STYLES`. Adding a style to
  `make_reference.py` does nothing unless something in `resume.md` references
  it, via a `#` heading level or a `custom-style` div.

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

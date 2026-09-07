#!/usr/bin/env python3
"""
Builds reference.docx: the visual design for the resume pipeline.

Starts from `pandoc --print-default-data-file reference.docx` (which contains
every style ID Pandoc knows how to emit) and restyles the ones the resume uses.
Pandoc discards this file's *content* and keeps its styles, numbering, and
page setup.

Edit the constants below to change the look of every resume you generate.
"""
import configparser
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
WORK = BUILD / "_refbuild"
CONFIG = ROOT / "presets.ini"

USAGE = "usage: make_reference.py [options] [output.docx]"

HELP = """usage: make_reference.py [options] [output.docx]

Generate the style carrier Pandoc reads for the design. Values come from
presets.ini; an environment variable of the same name in caps overrides one
for a single run.

options:
  --preset NAME     build with a named preset (default: DEFAULT)
  --list-presets    show the available presets and what each changes
  --set P.KEY=VAL   change a value in presets.ini and exit
  -h, --help        show this help and exit

With no output path this writes build/reference.docx, or
build/reference-<preset>.docx when --preset is given. An explicit path is
taken relative to the current directory.

examples:
  make_reference.py
  make_reference.py --preset roomy
  make_reference.py --set clean.bullet_right=1800
  SPACING=1.5 make_reference.py build/reference-test.docx
"""


def _infer_cast(raw):
    """Type of a key, taken from whatever [DEFAULT] holds for it."""
    for cast in (int, float):
        try:
            cast(raw)
            return cast
        except ValueError:
            continue
    return str


def set_value(spec):
    """--set PRESET.KEY=VALUE, edited in place.

    Written line by line rather than through configparser.write(), which
    discards every comment in the file. presets.ini is mostly comments
    explaining what the numbers mean, so losing them would cost more than the
    command is worth.
    """
    m = re.match(r"^([A-Za-z0-9_-]+)\.([A-Za-z0-9_]+)=(.*)$", spec)
    if not m:
        sys.exit(f"--set wants PRESET.KEY=VALUE, got {spec!r}\n{USAGE}")
    preset, key, value = m.group(1), m.group(2), m.group(3).strip()

    cp = configparser.ConfigParser(inline_comment_prefixes=("#", ";"))
    if not cp.read(CONFIG):
        sys.exit(f"cannot read {CONFIG}")
    if preset != "DEFAULT" and not cp.has_section(preset):
        known = ", ".join(["DEFAULT", *cp.sections()])
        sys.exit(f"no preset {preset!r}. Available: {known}")
    defaults = dict(cp["DEFAULT"])
    if key not in defaults:
        sys.exit(f"unknown key {key!r}. Valid keys: {', '.join(sorted(defaults))}")

    cast = _infer_cast(defaults[key])
    try:
        cast(value)
    except ValueError:
        sys.exit(f"{key} expects {cast.__name__}, got {value!r}")

    before = cp["DEFAULT"][key] if preset == "DEFAULT" else cp[preset][key]

    lines = CONFIG.read_text().split("\n")
    start = next((i for i, ln in enumerate(lines)
                  if ln.strip() == f"[{preset}]"), None)
    if start is None:
        sys.exit(f"no [{preset}] section in {CONFIG.name}")
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].lstrip().startswith("[")), len(lines))

    stale_comment = None
    pat = re.compile(r"^(\s*" + re.escape(key) + r"\s*=\s*)([^#;]*?)(\s*)([#;].*)?$")
    for i in range(start + 1, end):
        m2 = pat.match(lines[i])
        if not m2:
            continue
        head, old_val, gap, comment = m2.group(1), m2.group(2), m2.group(3), m2.group(4)
        if comment:
            # Any inline comment here may describe the old value -- often in
            # different units, like "# 1.5in" beside 2160 -- so matching on the
            # number itself misses the cases that matter. Flag them all and let
            # the reader judge.
            stale_comment = comment
            # Keep the comment in the column it already occupied.
            col = len(head) + len(old_val) + len(gap)
            pad = max(1, col - len(head) - len(value))
            lines[i] = head + value + " " * pad + comment
        else:
            lines[i] = head + value
        break
    else:
        # Key is inherited rather than stated here, so add it. Anchor to the
        # last actual key line, not the last non-blank one: a section is often
        # followed by the *next* section's leading comment, and inserting after
        # that would divorce the comment from what it describes.
        last_kv = start
        for j in range(start + 1, end):
            if re.match(r"^\s*[A-Za-z0-9_]+\s*=", lines[j]):
                last_kv = j
        lines.insert(last_kv + 1, f"{key} = {value}")

    CONFIG.write_text("\n".join(lines))
    print(f"{CONFIG.name}: [{preset}] {key}  {before} -> {value}", flush=True)
    if stale_comment:
        print(f"  note: kept the inline comment verbatim -- check it still "
              f"reads true: {stale_comment.strip()!r}", file=sys.stderr)


def list_presets():
    """Print each preset and only the keys it actually overrides."""
    cp = configparser.ConfigParser(inline_comment_prefixes=("#", ";"))
    if not cp.read(CONFIG):
        sys.exit(f"cannot read {CONFIG}")
    defaults = dict(cp["DEFAULT"])
    names = ["DEFAULT", *cp.sections()]
    width = max(len(n) for n in names)
    print(f"presets in {CONFIG.name}:\n")
    print(f"  {'DEFAULT':{width}}  the baseline design")
    for name in cp.sections():
        diff = [f"{k} = {v}" for k, v in cp[name].items() if defaults.get(k) != v]
        print(f"  {name:{width}}  {', '.join(diff) if diff else 'no overrides'}")


def parse_args(argv):
    """--preset NAME (or --preset=NAME), plus an optional output filename."""
    preset, out = "DEFAULT", None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            print(HELP, end="")
            sys.exit(0)
        if a == "--list-presets":
            list_presets()
            sys.exit(0)
        if a == "--set":
            i += 1
            if i >= len(argv):
                sys.exit(f"--set needs PRESET.KEY=VALUE\n{USAGE}")
            set_value(argv[i])
            sys.exit(0)
        if a.startswith("--set="):
            set_value(a.split("=", 1)[1])
            sys.exit(0)
        if a == "--preset":
            i += 1
            if i >= len(argv):
                sys.exit(f"--preset needs a name\n{USAGE}")
            preset = argv[i]
        elif a.startswith("--preset="):
            preset = a.split("=", 1)[1]
        elif a.startswith("-"):
            sys.exit(f"unknown option: {a}\n{USAGE}")
        else:
            out = a
        i += 1
    return preset, out


def load_preset(name):
    """One section of presets.ini, with [DEFAULT] inherited underneath."""
    cp = configparser.ConfigParser(inline_comment_prefixes=("#", ";"))
    if not cp.read(CONFIG):
        sys.exit(f"cannot read {CONFIG}")
    if name != "DEFAULT" and not cp.has_section(name):
        known = ", ".join(["DEFAULT", *cp.sections()])
        sys.exit(f"no preset {name!r} in {CONFIG.name}. Available: {known}")
    return cp["DEFAULT"] if name == "DEFAULT" else cp[name]


# ------------------------------------------------------------------- xml bits


def rfonts(font):
    return (f'<w:rFonts w:ascii="{font}" w:hAnsi="{font}" '
            f'w:eastAsia="{font}" w:cs="{font}"/>')


def style(sid, name, ppr, rpr, based="Normal", nxt="Normal"):
    return (
        f'<w:style w:type="paragraph" w:styleId="{sid}">'
        f'<w:name w:val="{name}"/>'
        f'<w:basedOn w:val="{based}"/><w:next w:val="{nxt}"/><w:qFormat/>'
        f'<w:pPr>{ppr}</w:pPr><w:rPr>{rpr}</w:rPr>'
        f'</w:style>'
    )


def design(cfg, env=None):
    """Build the style table for one preset.

    Everything numeric comes from presets.ini; an environment variable of
    the same name in caps overrides it. Nothing here runs at import time,
    so the module can be imported without parsing argv or reading config.
    """
    env = os.environ if env is None else env

    def knob(key, cast=str):
        """Preset value for `key`, overridden by the same name in caps if set."""
        return cast(env.get(key.upper(), cfg[key]))

    # ---------------------------------------------------------------- design knobs

    # Every value here comes from presets.ini -- see that file for what each one
    # means and how to add a preset of your own.

    BODY_FONT = knob("body_font")
    DISPLAY_FONT = knob("display_font")   # name, tagline, contact, headings
    BODY_SIZE = knob("body_size", int)
    PAGE_W = knob("page_width", int)
    PAGE_H = knob("page_height", int)
    MARGIN = knob("margin", int)
    RIGHT_TAB = PAGE_W - 2 * MARGIN  # where @@ sends the date

    # Vertical rhythm. SPACING scales every paragraph before/after value; LINE is
    # line height in 240ths (252 = 1.05 lines). Raise both to loosen a page that
    # reads tight. Both are overridable from the shell, so you can render a variant
    # without editing this file:
    #
    #   SPACING=1.75 LINE=276 python3 make_reference.py reference-roomy.docx
    #
    SPACING = knob("spacing", float)
    LINE = knob("line", int)

    # How far bullet text stops short of the right margin, in DXA. A full-width
    # 7.5" measure runs bullets right up against the date column and reads
    # crowded; pulling them in gives the dates a clear gutter. 0 restores
    # full-width bullets.
    BULLET_RIGHT = knob("bullet_right", int)


    def sp(v):
        """Scale a spacing value by SPACING, rounded to whole DXA."""
        return round(v * SPACING)

    # Every body paragraph carries a right tab stop at the margin, so the tab that
    # the Lua filter injects for @@ always lands in the same place.
    TABS = f'<w:tabs><w:tab w:val="right" w:pos="{RIGHT_TAB}"/></w:tabs>'

    # Bullets carry their own right tab stop, moved in by BULLET_RIGHT. Without
    # this a dated bullet would tab to a stop outside its own text area.
    BULLET_TABS = (f'<w:tabs><w:tab w:val="right" '
                   f'w:pos="{RIGHT_TAB - BULLET_RIGHT}"/></w:tabs>')

    STYLES = {
        # id: (name, pPr, rPr)
        "Normal": (
            "Normal",
            f'{TABS}<w:spacing w:before="0" w:after="0" w:line="{LINE}" w:lineRule="auto"/>',
            f'{rfonts(BODY_FONT)}<w:sz w:val="{BODY_SIZE}"/><w:szCs w:val="{BODY_SIZE}"/>',
        ),
        # First paragraph after a heading: no extra space, the heading supplies it.
        "FirstParagraph": (
            "First Paragraph",
            f'{TABS}<w:spacing w:before="0" w:after="0"/>',
            "",
        ),
        # Subsequent paragraphs: this is the gap between entries within a section.
        "BodyText": (
            "Body Text",
            f'{TABS}<w:spacing w:before="{sp(120)}" w:after="0"/>',
            "",
        ),
        # Tight list items (bullets). The w:ind is what actually controls bullet
        # indent: Pandoc generates its own numbering definitions at write time and
        # ignores the ones in the reference doc, but a style's own indent still
        # wins over the numbering's. Order matters -- OOXML wants tabs, spacing,
        # then ind.
        "Compact": (
            "Compact",
            (f'{BULLET_TABS}<w:spacing w:before="0" w:after="{sp(20)}"/>'
             f'<w:ind w:left="288" w:right="{BULLET_RIGHT}" w:hanging="180"/>'),
            "",
        ),
        # Section headings: bold caps on a full-width rule, kept with what follows.
        "Heading1": (
            "Heading 1",
            ('<w:keepNext/>'
             '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="3" w:color="000000"/></w:pBdr>'
             f'<w:spacing w:before="{sp(220)}" w:after="{sp(80)}"/>'
             '<w:outlineLvl w:val="0"/>'),
            (f'{rfonts(DISPLAY_FONT)}<w:b/><w:bCs/><w:caps/>'
             f'<w:color w:val="000000"/><w:spacing w:val="40"/>'
             f'<w:sz w:val="21"/><w:szCs w:val="21"/>'),
        ),
        # Company headings inside a section: bold, no rule -- the rule stays
        # exclusive to Heading1 so the two levels never compete. TABS is required
        # here or @@ has no right stop to land on inside a heading.
        "Heading2": (
            "Heading 2",
            ('<w:keepNext/>'
             f'{TABS}'
             f'<w:spacing w:before="{sp(140)}" w:after="{sp(40)}"/>'
             '<w:outlineLvl w:val="1"/>'),
            (f'{rfonts(DISPLAY_FONT)}<w:b/><w:bCs/>'
             f'<w:color w:val="000000"/>'
             f'<w:sz w:val="22"/><w:szCs w:val="22"/>'),
        ),
        "Name": (
            "Name",
            f'<w:spacing w:before="0" w:after="{sp(40)}"/>',
            (f'{rfonts(DISPLAY_FONT)}<w:b/><w:bCs/><w:spacing w:val="10"/>'
             f'<w:sz w:val="40"/><w:szCs w:val="40"/>'),
        ),
        "Tagline": (
            "Tagline",
            f'<w:spacing w:before="0" w:after="{sp(40)}"/>',
            (f'{rfonts(DISPLAY_FONT)}<w:caps/><w:color w:val="555555"/>'
             f'<w:spacing w:val="30"/><w:sz w:val="21"/><w:szCs w:val="21"/>'),
        ),
        "Contact": (
            "Contact",
            '<w:spacing w:before="0" w:after="0"/>',
            f'{rfonts(DISPLAY_FONT)}<w:sz w:val="19"/><w:szCs w:val="19"/>',
        ),
    }

    SECT_PR = (
        f'<w:sectPr>'
        f'<w:pgSz w:w="{PAGE_W}" w:h="{PAGE_H}" w:orient="portrait"/>'
        f'<w:pgMar w:top="{MARGIN}" w:right="{MARGIN}" w:bottom="{MARGIN}" '
        f'w:left="{MARGIN}" w:header="{MARGIN}" w:footer="{MARGIN}" w:gutter="0"/>'
        f'</w:sectPr>'
    )

    return {
        "styles": STYLES,
        "sect_pr": SECT_PR,
        "body_font": BODY_FONT,
        "body_size": BODY_SIZE,
    }
# --------------------------------------------------------------------- build


def main(argv=None):
    preset, out_name = parse_args(sys.argv[1:] if argv is None else argv)
    cfg = load_preset(preset)
    d = design(cfg)
    styles, sect_pr = d["styles"], d["sect_pr"]
    body_font, body_size = d["body_font"], d["body_size"]

    if out_name is None:
        out_name = ("reference.docx" if preset == "DEFAULT"
                    else f"reference-{preset}.docx")
        out = BUILD / out_name
    else:
        out = Path(out_name)          # explicit paths are relative to the cwd
    out.parent.mkdir(parents=True, exist_ok=True)

    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)

    base = WORK / "base.docx"
    with open(base, "wb") as fh:
        subprocess.run(["pandoc", "--print-default-data-file", "reference.docx"],
                       stdout=fh, check=True)

    unpacked = WORK / "unpacked"
    with zipfile.ZipFile(base) as z:
        z.extractall(unpacked)

    # ---- styles.xml: replace each target style outright (no duplicates) ----
    spath = unpacked / "word" / "styles.xml"
    s = spath.read_text(encoding="utf-8")

    for sid, (name, ppr, rpr) in styles.items():
        based = "Normal" if sid != "Normal" else None
        if based:
            new = style(sid, name, ppr, rpr)
        else:
            new = (f'<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
                   f'<w:name w:val="Normal"/><w:qFormat/>'
                   f'<w:pPr>{ppr}</w:pPr><w:rPr>{rpr}</w:rPr></w:style>')

        pattern = re.compile(
            r'<w:style [^>]*w:styleId="' + re.escape(sid) + r'".*?</w:style>',
            re.DOTALL)
        if pattern.search(s):
            s = pattern.sub(new, s, count=1)
        else:
            s = s.replace("</w:styles>", new + "</w:styles>")

        assert s.count(f'w:styleId="{sid}"') == 1, f"duplicate style {sid}"

    # Document defaults, so anything unstyled still inherits the body font.
    s = re.sub(
        r'<w:docDefaults>.*?</w:docDefaults>',
        '<w:docDefaults><w:rPrDefault><w:rPr>'
        + rfonts(body_font)
        + f'<w:sz w:val="{body_size}"/><w:szCs w:val="{body_size}"/>'
        + '</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr/></w:pPrDefault></w:docDefaults>',
        s, flags=re.DOTALL)

    spath.write_text(s, encoding="utf-8")

    # ---- numbering.xml: real bullet glyph, tighter indent ----
    # Pandoc regenerates list numbering, so this only takes effect for
    # writers that reuse the reference doc's definitions. The indent that
    # reaches the DOCX comes from the Compact style above.
    npath = unpacked / "word" / "numbering.xml"
    n = npath.read_text(encoding="utf-8")

    def fix_bullet(m):
        block = m.group(0)
        if not re.search(r'<w:numFmt\s+w:val="bullet"', block):
            return block
        block = re.sub(r'<w:lvlText w:val="[^"]*"\s*/>',
                       '<w:lvlText w:val="\u2022"/>', block, count=1)
        block = re.sub(r'<w:ind [^/]*/>',
                       '<w:ind w:left="288" w:hanging="180"/>', block)
        # Drop the legacy num tab stop; it widens the bullet-to-text gap.
        block = re.sub(r'<w:tabs>\s*<w:tab w:val="num"[^/]*/>\s*</w:tabs>', '', block)
        return block

    n = re.sub(r'<w:lvl w:ilvl="0".*?</w:lvl>', fix_bullet, n, flags=re.DOTALL)
    npath.write_text(n, encoding="utf-8")

    # ---- document.xml: page size and margins ----
    dpath = unpacked / "word" / "document.xml"
    d = dpath.read_text(encoding="utf-8")
    # The skeleton ships a self-closing <w:sectPr />, so handle both forms.
    if re.search(r'<w:sectPr\b[^>]*/>', d):
        d = re.sub(r'<w:sectPr\b[^>]*/>', sect_pr, d, count=1)
    elif "<w:sectPr" in d:
        d = re.sub(r'<w:sectPr.*?</w:sectPr>', sect_pr, d, flags=re.DOTALL, count=1)
    else:
        d = d.replace("</w:body>", sect_pr + "</w:body>")
    assert 'w:pgMar' in d, "page setup not applied"
    dpath.write_text(d, encoding="utf-8")

    # ---- repack ----
    if out.exists():
        out.unlink()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(unpacked.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(unpacked))

    shutil.rmtree(WORK)
    print(f"wrote {out} [preset: {preset}]")


if __name__ == "__main__":
    main()

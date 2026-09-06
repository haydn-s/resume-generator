#!/usr/bin/env python3
"""
Builds reference.docx: the visual design for the resume pipeline.

Starts from `pandoc --print-default-data-file reference.docx` (which contains
every style ID Pandoc knows how to emit) and restyles the ones the resume uses.
Pandoc discards this file's *content* and keeps its styles, numbering, and
page setup.

Edit the constants below to change the look of every resume you generate.
"""
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).parent
WORK = HERE / "_refbuild"
OUT = HERE / (sys.argv[1] if len(sys.argv) > 1 else "reference.docx")

# ---------------------------------------------------------------- design knobs

BODY_FONT = "Calibri"
DISPLAY_FONT = "Arial"          # name, tagline, contact line, section headings
BODY_SIZE = 21                  # half-points -> 10.5pt
PAGE_W, PAGE_H = 12240, 15840   # US Letter, in DXA (1440 = 1 inch)
MARGIN = 720                    # 0.5 inch
RIGHT_TAB = PAGE_W - 2 * MARGIN  # 10800 -> where @@ sends the date

# Vertical rhythm. SPACING scales every paragraph before/after value; LINE is
# line height in 240ths (252 = 1.05 lines). Raise both to loosen a page that
# reads tight. Both are overridable from the shell, so you can render a variant
# without editing this file:
#
#   SPACING=1.75 LINE=276 python3 make_reference.py reference-roomy.docx
#
SPACING = float(os.environ.get("SPACING", 1.0))
LINE = int(os.environ.get("LINE", 252))


def sp(v):
    """Scale a spacing value by SPACING, rounded to whole DXA."""
    return int(round(v * SPACING))

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


# Every body paragraph carries a right tab stop at the margin, so the tab that
# the Lua filter injects for @@ always lands in the same place.
TABS = f'<w:tabs><w:tab w:val="right" w:pos="{RIGHT_TAB}"/></w:tabs>'

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
        f'{TABS}<w:spacing w:before="0" w:after="{sp(20)}"/>'
        f'<w:ind w:left="288" w:hanging="180"/>',
        "",
    ),
    # Section headings: bold caps on a full-width rule, kept with what follows.
    "Heading1": (
        "Heading 1",
        '<w:keepNext/>'
        '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="3" w:color="000000"/></w:pBdr>'
        f'<w:spacing w:before="{sp(220)}" w:after="{sp(80)}"/>'
        '<w:outlineLvl w:val="0"/>',
        f'{rfonts(DISPLAY_FONT)}<w:b/><w:bCs/><w:caps/>'
        f'<w:color w:val="000000"/><w:spacing w:val="40"/>'
        f'<w:sz w:val="21"/><w:szCs w:val="21"/>',
    ),
    # Company headings inside a section: bold, no rule -- the rule stays
    # exclusive to Heading1 so the two levels never compete. TABS is required
    # here or @@ has no right stop to land on inside a heading.
    "Heading2": (
        "Heading 2",
        '<w:keepNext/>'
        f'{TABS}'
        f'<w:spacing w:before="{sp(140)}" w:after="{sp(40)}"/>'
        '<w:outlineLvl w:val="1"/>',
        f'{rfonts(DISPLAY_FONT)}<w:b/><w:bCs/>'
        f'<w:color w:val="000000"/>'
        f'<w:sz w:val="22"/><w:szCs w:val="22"/>',
    ),
    "Name": (
        "Name",
        f'<w:spacing w:before="0" w:after="{sp(40)}"/>',
        f'{rfonts(DISPLAY_FONT)}<w:b/><w:bCs/><w:spacing w:val="10"/>'
        f'<w:sz w:val="40"/><w:szCs w:val="40"/>',
    ),
    "Tagline": (
        "Tagline",
        f'<w:spacing w:before="0" w:after="{sp(40)}"/>',
        f'{rfonts(DISPLAY_FONT)}<w:caps/><w:color w:val="555555"/>'
        f'<w:spacing w:val="30"/><w:sz w:val="21"/><w:szCs w:val="21"/>',
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

# --------------------------------------------------------------------- build


def main():
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir()

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

    for sid, (name, ppr, rpr) in STYLES.items():
        based = "Normal" if sid != "Normal" else None
        if based:
            new = style(sid, name, ppr, rpr)
        else:
            new = (f'<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
                   f'<w:name w:val="Normal"/><w:qFormat/>'
                   f'<w:pPr>{ppr}</w:pPr><w:rPr>{rpr}</w:rPr></w:style>')

        pattern = re.compile(
            r'<w:style [^>]*w:styleId="' + re.escape(sid) + r'".*?</w:style>',
            re.S)
        if pattern.search(s):
            s = pattern.sub(new, s, count=1)
        else:
            s = s.replace("</w:styles>", new + "</w:styles>")

        assert s.count(f'w:styleId="{sid}"') == 1, f"duplicate style {sid}"

    # Document defaults, so anything unstyled still inherits the body font.
    s = re.sub(
        r'<w:docDefaults>.*?</w:docDefaults>',
        '<w:docDefaults><w:rPrDefault><w:rPr>'
        + rfonts(BODY_FONT)
        + f'<w:sz w:val="{BODY_SIZE}"/><w:szCs w:val="{BODY_SIZE}"/>'
        + '</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr/></w:pPrDefault></w:docDefaults>',
        s, flags=re.S)

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

    n = re.sub(r'<w:lvl w:ilvl="0".*?</w:lvl>', fix_bullet, n, flags=re.S)
    npath.write_text(n, encoding="utf-8")

    # ---- document.xml: page size and margins ----
    dpath = unpacked / "word" / "document.xml"
    d = dpath.read_text(encoding="utf-8")
    # The skeleton ships a self-closing <w:sectPr />, so handle both forms.
    if re.search(r'<w:sectPr\b[^>]*/>', d):
        d = re.sub(r'<w:sectPr\b[^>]*/>', SECT_PR, d, count=1)
    elif "<w:sectPr" in d:
        d = re.sub(r'<w:sectPr.*?</w:sectPr>', SECT_PR, d, flags=re.S, count=1)
    else:
        d = d.replace("</w:body>", SECT_PR + "</w:body>")
    assert 'w:pgMar' in d, "page setup not applied"
    dpath.write_text(d, encoding="utf-8")

    # ---- repack ----
    if OUT.exists():
        OUT.unlink()
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(unpacked.rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(unpacked))

    shutil.rmtree(WORK)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()

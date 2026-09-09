"""Inspect a generated DOCX. Stdlib only, and kept 3.9-compatible."""
import re
import sys
import zipfile

USAGE = "usage: docx.py {styles|tabs|literal-at|math|text|style-attr} FILE [args]"


def read(path, part):
    with zipfile.ZipFile(path) as z:
        return z.read("word/" + part).decode("utf-8")


def main(argv):
    if len(argv) < 2:
        sys.exit(USAGE)
    cmd, path = argv[0], argv[1]
    if cmd == "styles":
        doc = read(path, "document.xml")
        for s in sorted(set(re.findall(r'w:pStyle w:val="([^"]+)"', doc))):
            print(s)
    elif cmd == "tabs":
        print(len(re.findall(r"<w:tab/>", read(path, "document.xml"))))
    elif cmd == "literal-at":
        print(read(path, "document.xml").count("@@"))
    elif cmd == "math":
        print(len(re.findall(r"<m:oMath>", read(path, "document.xml"))))
    elif cmd == "text":
        # Word runs only. Equation text lives in <m:t>, and leaving it out is
        # the point: this is the document as a w:t-walking reader sees it.
        doc = read(path, "document.xml")
        print(" ".join(re.findall(r"<w:t[^>]*>(.*?)</w:t>", doc, re.DOTALL)))
    elif cmd == "style-attr":
        sid, attr = argv[2], argv[3]
        pattern = rf'w:styleId="{re.escape(sid)}".*?</w:style>'
        blk = re.search(pattern, read(path, "styles.xml"), re.DOTALL)
        if not blk:
            sys.exit("no such style: " + sid)
        m = re.search(rf'{re.escape(attr)}="([^"]+)"', blk.group(0))
        print(m.group(1) if m else "")
    else:
        sys.exit(USAGE)


if __name__ == "__main__":
    main(sys.argv[1:])

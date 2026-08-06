"""Extract readable text from Word survey instruments.

Writes one <PREFIX>.txt per .docx, each line prefixed with its index in the
document so a later coverage check can point at a line.

Usage:
    python3 extract_instrument_text.py <instrument_dir> <output_dir>

Two things in these files break naive extraction, and both are handled here:

mc:Fallback
    A text box is stored twice, once under mc:Choice and once under
    mc:Fallback. Reading both returns every line in the box twice. WX24 keeps
    its codebook appendix in a text box, so the appendix appeared twice before
    this was fixed.

Nested w:p
    The paragraph that anchors a text box contains the box's own paragraphs as
    descendants. Collecting every w:t below it concatenates the whole box onto
    one line. Only the runs whose nearest w:p ancestor is the paragraph itself
    belong to it.

w:br is a line break inside a paragraph, not a new paragraph, so it is split
on. Word writes option lists that way in some instruments.
"""

import os
import sys
import xml.etree.ElementTree as ET
import zipfile

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
MC = "{http://schemas.openxmlformats.org/markup-compatibility/2006}"


def document_lines(path):
    root = ET.fromstring(zipfile.ZipFile(path).read("word/document.xml"))

    for parent in root.iter():
        for child in list(parent):
            if child.tag == MC + "Fallback":
                parent.remove(child)

    parents = {child: parent for parent in root.iter() for child in parent}

    def paragraph_depth(node):
        depth = 0
        cursor = parents.get(node)
        while cursor is not None:
            if cursor.tag == W + "p":
                depth += 1
            cursor = parents.get(cursor)
        return depth

    lines = []
    for paragraph in root.iter(W + "p"):
        depth = paragraph_depth(paragraph)
        parts = []
        for node in paragraph.iter():
            if node is paragraph or node.tag not in (W + "t", W + "br", W + "tab"):
                continue
            if paragraph_depth(node) != depth + 1:
                continue
            if node.tag == W + "t":
                parts.append(node.text or "")
            elif node.tag == W + "br":
                parts.append("\n")
            else:
                parts.append(" ")
        text = "".join(parts).replace("\u00a0", " ")
        lines.extend(text.split("\n"))

    return [" ".join(line.split()) for line in lines]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)

    instrument_dir, output_dir = sys.argv[1], sys.argv[2]
    os.makedirs(output_dir, exist_ok=True)

    names = sorted(n for n in os.listdir(instrument_dir) if n.endswith(".docx"))
    if not names:
        sys.exit("No .docx files in " + instrument_dir)

    for name in names:
        lines = document_lines(os.path.join(instrument_dir, name))
        prefix = name.split()[0]
        destination = os.path.join(output_dir, prefix + ".txt")
        with open(destination, "w") as handle:
            for index, line in enumerate(lines):
                if line:
                    handle.write("%d\t%s\n" % (index, line))
        print("%-8s %5d lines -> %s" % (prefix, len(lines), destination))


if __name__ == "__main__":
    main()

"""Rewrite a font's family name so it can stand in for another family.

xochitl's font picker is a curated list of labels, not a scan of the font
directory, so a newly added font can never appear in it. The way in is to hand
a font the family name the picker already asks for -- then the entry is still
called what it was called, but the glyphs are yours.

Only the name table is touched; outlines, metrics and the variable axes are
left exactly as they were.

    python3 retag-family.py <in.ttf> <out.ttf> <family> [style]
"""

import sys

from fontTools.ttLib import TTFont

# nameID 2 (subfamily) and 17 (typographic subfamily) are deliberately left
# alone: the source font already describes its own slant and weight correctly,
# and rewriting them is how you end up with an italic that reports as upright.
FAMILY_IDS = (1, 16)  # family, typographic family
UNIQUE_ID = 3
FULL_NAME = 4
POSTSCRIPT = 6


def retag(src: str, dst: str, family: str, style: str = "Regular") -> None:
    font = TTFont(src)
    name = font["name"]
    postscript = f"{family}-{style}".replace(" ", "")

    for record in list(name.names):
        args = (record.platformID, record.platEncID, record.langID)
        if record.nameID in FAMILY_IDS:
            name.setName(family, record.nameID, *args)
        elif record.nameID == FULL_NAME:
            name.setName(f"{family} {style}", record.nameID, *args)
        elif record.nameID == POSTSCRIPT:
            name.setName(postscript, record.nameID, *args)
        elif record.nameID == UNIQUE_ID:
            # Keep this distinct from the font it replaces, so a font cache
            # can still tell the two apart.
            name.setName(f"{postscript};retagged", record.nameID, *args)

    font.save(dst)


if __name__ == "__main__":
    if not 4 <= len(sys.argv) <= 5:
        sys.exit(__doc__)
    retag(sys.argv[1], sys.argv[2], sys.argv[3], *sys.argv[4:])

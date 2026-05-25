#!/usr/bin/env python3
"""Post-process a drawio-exported SVG to produce a portable, light-themed image.

drawio-desktop 30.0.2's CLI emits SVGs whose root carries
``background: transparent`` and whose text/label styles use the CSS
``light-dark(<light>, <dark>)`` function. Viewers that ignore ``color-scheme:
light`` on an SVG root then render text in the dark-mode value, which collides
with the transparent canvas. This helper rewrites the SVG so it renders the
same way everywhere:

* injects a white ``<rect>`` covering the viewport as the first child of
  ``<svg>``, so the page background is opaque regardless of viewer behaviour
* replaces ``background[-color]: transparent`` in the root style with
  ``#ffffff`` for consistency with the injected rect
* flattens every ``light-dark(A, B)`` to ``A`` with balanced-paren awareness
  (so ``light-dark(rgb(0,0,0), rgb(255,255,255))`` and
  ``light-dark(#fff, var(--x, #121212))`` are handled correctly)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

_SVG_OPEN_RE = re.compile(r'(<svg xmlns="http://www\.w3\.org/2000/svg"[^>]*>)')
_BACKGROUND_RECT = '<rect width="100%" height="100%" fill="#ffffff"/>'


def flatten_light_dark(text: str) -> str:
    """Replace every ``light-dark(A, B)`` with its first argument.

    The arguments may themselves contain balanced parentheses and commas
    (``rgb(...)``, ``var(...)``), so a naive regex is not enough. This
    walks the string, tracking paren depth, and emits the substring
    between the opening paren and the top-level comma.
    """
    needle = 'light-dark('
    out: list[str] = []
    i = 0
    while True:
        idx = text.find(needle, i)
        if idx == -1:
            out.append(text[i:])
            return ''.join(out)
        out.append(text[i:idx])
        j = idx + len(needle)
        arg_start = j
        depth = 1
        comma_at = -1
        end = -1
        while j < len(text):
            c = text[j]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    end = j
                    break
            elif c == ',' and depth == 1 and comma_at == -1:
                comma_at = j
            j += 1
        if end == -1 or comma_at == -1:
            out.append(text[idx:end + 1 if end != -1 else len(text)])
            i = (end + 1) if end != -1 else len(text)
            continue
        out.append(text[arg_start:comma_at].strip())
        i = end + 1


def postprocess(svg: str) -> str:
    svg = flatten_light_dark(svg)
    svg = svg.replace('background: transparent', 'background: #ffffff')
    svg = svg.replace('background-color: transparent', 'background-color: #ffffff')
    svg, n = _SVG_OPEN_RE.subn(r'\1' + _BACKGROUND_RECT, svg, count=1)
    if n != 1:
        raise SystemExit('postprocess_drawio_svg: did not find a recognizable <svg> root')
    return svg


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print('usage: postprocess_drawio_svg.py <svg_file>', file=sys.stderr)
        return 1
    path = Path(argv[1])
    path.write_text(postprocess(path.read_text()))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

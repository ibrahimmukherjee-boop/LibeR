"""Build the Windows installer icon from the canonical LibeR dove asset."""

from __future__ import annotations

import argparse
import base64
import io
import re
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    svg = args.source.read_text(encoding="utf-8")
    match = re.search(r'href="data:image/png;base64,([^"]+)"', svg)
    if match is None:
        raise SystemExit("The canonical SVG does not contain an embedded PNG.")
    image = Image.open(io.BytesIO(base64.b64decode(match.group(1)))).convert("RGBA")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(
        args.output,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check that native session separators are painted, not merely spaced."""
import json
import sys
from pathlib import Path
sys.dont_write_bytecode = True

from native_png import read_png

width, height, rows = read_png(sys.argv[1])

geometry = json.loads(Path(sys.argv[2]).read_text())
scale = geometry["header"]["viewport"]["deviceScaleFactor"]
assert len(geometry["elements"]) == 2, "Expected two session headers"
for index, element in enumerate(geometry["elements"]):
    assert element["visible"]
    x, y, w, _ = element["rect"]
    start, end, top = round((x + 4) * scale), round((x + w - 4) * scale), round(y * scale)
    contrast = []
    for sample_y in range(top, top + round(scale)):
        different = sum(max(abs(rows[sample_y][sample_x * 4 + channel] - rows[top - 2 * round(scale)][sample_x * 4 + channel]) for channel in range(3)) >= 16 for sample_x in range(start, end))
        contrast.append(different / (end - start))
    painted = max(contrast) >= 0.9
    assert painted == (index > 0), f"Session {index + 1}: expected separator={index > 0}, observed={painted}"
print("Session separator pixels: first header unlined, second header painted PASS")

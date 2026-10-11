#!/usr/bin/env python3
"""Check painted group/pane name alignment and both pane title lines."""
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from native_png import read_png

groups = json.loads(Path(sys.argv[1]).read_text())
pane = json.loads(Path(sys.argv[2]).read_text())
width, height, pixels = read_png(sys.argv[3])
scale = pane["header"]["viewport"]["deviceScaleFactor"]
row = pane["elements"][0]["rect"]
group = min(groups["elements"], key=lambda item: abs(item["rect"][1] - row[1]))["rect"]


def ink_lines(rect):
    x, y, w, h = rect
    # Exclude the independent mark gutter and the one-pixel group border.
    left, right = round((x + 14) * scale), round((x + w - 2) * scale)
    active = []
    for py in range(round((y + 5) * scale), round((y + h - 5) * scale)):
        line = pixels[py]
        background = tuple(line[right * 4:right * 4 + 3])
        ink = [px for px in range(left, right)
               if max(abs(a - b) for a, b in zip(line[px * 4:px * 4 + 3], background)) > 40]
        if ink:
            active.append((py, min(ink)))
    lines = []
    for py, px in active:
        if not lines or py > lines[-1][0] + 1:
            lines.append([py, px])
        else:
            lines[-1] = [py, min(px, lines[-1][1])]
    return [px / scale for _, px in lines]


group_lines = ink_lines(group)
pane_lines = ink_lines(row)
assert group_lines, "Group name did not paint"
assert len(pane_lines) == 2, f"Expected two painted title lines, got {pane_lines}"
assert abs(group_lines[0] - pane_lines[0]) <= 2, f"Group/pane name starts differ: {group_lines}, {pane_lines}"
assert abs(pane_lines[0] - pane_lines[1]) <= 2, f"Wrapped title is indented: {pane_lines}"
print("Native name columns: group/pane and wrapped title alignment PASS")

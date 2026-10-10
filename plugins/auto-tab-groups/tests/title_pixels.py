#!/usr/bin/env python3
"""Check actual topbar paint, including fixed-title clipping and focus transitions."""
import sys
sys.dont_write_bytecode = True
from native_png import read_png

mode, viewport, before, after = sys.argv[1:]
width, height, a = read_png(before)
w, h, b = read_png(after)
assert (width, height) == (w, h)
scale = width / int(viewport)
# The center strip contains no native controls, even when the title is hidden at 800px.
half = min(150, max(20, int(viewport) / 2 - 480))
left, right = round(width / 2 - half * scale), round(width / 2 + half * scale)
changed = []
for y in range(round(40 * scale)):
    for x in range(left, right):
        if a[y][x * 4:x * 4 + 4] != b[y][x * 4:x * 4 + 4]:
            changed.append((x, y))
if mode == "same":
    assert not changed, "Topbar title did not return to the expected paint"
else:
    assert changed, "Title missing, clipped, or stale in native screenshot"
    if mode == "center":
        xs, ys = zip(*changed)
        assert abs((min(xs) + max(xs) + 1) / 2 - width / 2) <= 3 * scale, "Title not centered on whole window"
        assert min(ys) > 0 and max(ys) < 40 * scale, "Title outside topbar"
print(f"Native title pixels: {mode} PASS")

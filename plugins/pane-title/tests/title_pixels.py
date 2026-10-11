#!/usr/bin/env python3
"""Check actual topbar paint, including fixed-title clipping and focus transitions."""
import json
import sys
sys.dont_write_bytecode = True
from native_png import read_png

mode, viewport, before, after = sys.argv[1:5]
width, height, a = read_png(before)
w, h, b = read_png(after)
assert (width, height) == (w, h)
scale = width / int(viewport)
# The center strip contains no native controls, even when the title is hidden at 800px.
half = min(300 if mode == "native" else 150, max(20, int(viewport) / 2 - 480))
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
    if mode in {"center", "native"}:
        xs, ys = zip(*changed)
        if mode == "center":
            assert abs((min(xs) + max(xs) + 1) / 2 - width / 2) <= 3 * scale, "Title not centered on whole window"
        assert min(ys) > 0 and max(ys) < 40 * scale, "Title outside topbar"
    if mode == "native":
        with open(sys.argv[5]) as file:
            geometry = json.load(file)
        group = next(element for element in geometry["elements"] if element["path"].endswith("div.tb-tabs"))
        icon = next(element for element in geometry["elements"] if ">span.tn-dk." in element["path"])
        x, y, group_width, group_height = group["rect"]
        assert abs(x + group_width / 2 - int(viewport) / 2) <= 1, "Native title group is not centered"
        assert 20 < group_width <= min(600, int(viewport) - 960) + 1, "Native title exceeds safe area"
        assert group_height == 40, "Native title changes topbar height"
        # Native ellipsis bearings need not be symmetric; center the full title box.
        assert min(xs) >= (x - 2) * scale and max(xs) < (x + group_width + 2) * scale, "Paint escapes centered native title box"
        ix, iy, iw, ih = icon["rect"]
        assert icon["visible"] and iw > 0 and ih > 0, "Native icon is hidden"
        assert ix >= x - 1 and ix + iw <= x + group_width + 1, "Native icon is clipped"
        pixels = []
        painted = 0
        for py in range(round(iy * scale), round((iy + ih) * scale)):
            for px in range(round(ix * scale), round((ix + iw) * scale)):
                pixel = b[py][px * 4:px * 4 + 4]
                pixels.append(pixel)
                painted += pixel != a[py][px * 4:px * 4 + 4]
        assert painted >= 4 * scale * scale, "Native icon did not actually paint"
        if sys.argv[6] == "vim":
            green = sum(pixel[1] > pixel[0] + 25 and pixel[1] > pixel[2] + 15 for pixel in pixels)
            assert green > len(pixels) / 20, "Real Vim did not produce its native green application icon"
print(f"Native title pixels: {mode} PASS")

#!/usr/bin/env python3
"""Verify native pane lamps turn off after read and leave title placement stable."""
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from native_png import read_png

def has_paint(region):
    colors = {tuple(row_bytes[offset:offset + 3])
              for row_bytes in region
              for offset in range(0, len(row_bytes), 4)}
    return len(colors) > 1

geometry = json.loads(Path(sys.argv[1]).read_text())
shots = [read_png(path) for path in sys.argv[2:]]
width, height, pixels = shots[0]
assert all((w, h) == (width, height) for w, h, _ in shots), "Screenshot dimensions changed"
scale = geometry["header"]["viewport"]["deviceScaleFactor"]
row = geometry["elements"][0]["rect"]
x, y, row_width, row_height = row
left = round(x * scale)
top = round(y * scale)
bottom = round((y + row_height) * scale)
assert bottom <= height and left + round(row_width * scale) <= width, "Pane row is outside screenshot"

def crop(image, x1, x2):
    return [line[round((x + x1) * scale) * 4:round((x + x2) * scale) * 4]
            for line in image[top:bottom]]

def state_paint(image):
    return crop(image, 2, 13)

def title_paint(image):
    return crop(image, 18, row_width - 7)

states = [state_paint(image) for _, _, image in shots]
if len(shots) == 2:
    assert has_paint(states[0]), "Unread notification lamp did not paint"
    assert not has_paint(states[1]), "Seen notification left a lit lamp behind"
    assert has_paint(title_paint(pixels)), "Pane title did not paint"
    sys.exit(0)
if len(shots) > 5:
    assert all(has_paint(state) for state in states), "Working lamp disappears during breathing"
    levels = {b"".join(state) for state in states}
    assert len(levels) >= 3, "Working lamp is static or blinking instead of breathing"
    titles = [title_paint(image) for _, _, image in shots]
    assert all(title == titles[0] for title in titles[1:]), "Breathing changes pane title paint"
    assert has_paint(titles[0]), "Pane title did not paint"
    print("Working lamp: sustained multi-level breathing with stable title PASS")
    sys.exit(0)

assert len(shots) == 5, "Expected inactive/busy/inactive/busy/inactive screenshots"
assert not has_paint(states[0]), "Inactive pane still has a lit lamp"
assert has_paint(states[1]), "Working pane has no lamp"
assert states[0] == states[2] == states[4], "Inactive indicator paint was not repeatable"
assert has_paint(states[3]), "Restarted working pane has no lamp"
assert states[0] != states[1], "Busy and inactive states produced identical indicator pixels"

stable = [title_paint(image) for _, _, image in shots]
assert all(value == stable[0] for value in stable[1:]), "Title paint or position changed with terminal state"
assert has_paint(stable[0]), "Pane title region is blank"

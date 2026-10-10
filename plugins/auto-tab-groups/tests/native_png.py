"""Decode Tern's native RGBA8 screenshots for consumer-visible pixel checks."""
import struct
import zlib
from pathlib import Path


def read_png(path):
    png = Path(path).read_bytes()
    assert png[:8] == b"\x89PNG\r\n\x1a\n"
    pos, compressed = 8, bytearray()
    while pos < len(png):
        size = struct.unpack_from(">I", png, pos)[0]
        kind, body = png[pos + 4:pos + 8], png[pos + 8:pos + 8 + size]
        if kind == b"IHDR":
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", body)
            assert (depth, color, compression, filtering, interlace) == (8, 6, 0, 0, 0), "Expected native RGBA8 PNG"
        elif kind == b"IDAT":
            compressed.extend(body)
        pos += size + 12
    raw = zlib.decompress(compressed)
    stride = width * 4
    rows, previous = [], bytearray(stride)
    for y in range(height):
        offset = y * (stride + 1)
        mode = raw[offset]
        assert mode <= 4, "Unknown PNG filter"
        row = bytearray(raw[offset + 1:offset + 1 + stride])
        if mode:
            for x in range(stride):
                left, up, corner = (row[x - 4] if x >= 4 else 0), previous[x], (previous[x - 4] if x >= 4 else 0)
                if mode == 1:
                    predictor = left
                elif mode == 2:
                    predictor = up
                elif mode == 3:
                    predictor = (left + up) // 2
                else:
                    p = left + up - corner
                    distances = [abs(p - left), abs(p - up), abs(p - corner)]
                    predictor = [left, up, corner][distances.index(min(distances))]
                row[x] = (row[x] + predictor) & 255
        rows.append(row)
        previous = row
    return width, height, rows

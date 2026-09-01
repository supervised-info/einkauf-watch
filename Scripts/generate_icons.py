#!/usr/bin/env python3
"""Platzhalter-App-Icon (navy, Haken) für iOS + Watch."""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAVY = (13, 31, 110, 255)
WHITE = (255, 255, 255, 255)


def dist_to_segment(px, py, x1, y1, x2, y2) -> float:
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return ((px - x1) ** 2 + (py - y1) ** 2) ** 0.5
    t = max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)))
    qx, qy = x1 + t * dx, y1 + t * dy
    return ((px - qx) ** 2 + (py - qy) ** 2) ** 0.5


def write_png(path: Path, size: int = 1024) -> None:
    raw = bytearray()
    thickness = size * 0.06
    a = (size * 0.28, size * 0.52)
    b = (size * 0.44, size * 0.72)
    c = (size * 0.76, size * 0.32)
    for y in range(size):
        raw.append(0)
        for x in range(size):
            d = min(dist_to_segment(x, y, *a, *b), dist_to_segment(x, y, *b, *c))
            if d <= thickness:
                raw.extend(WHITE)
            else:
                raw.extend(NAVY)

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def main() -> None:
    write_png(ROOT / "Sources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    write_png(ROOT / "Sources/Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    print("Wrote AppIcon.png for iOS and Watch")


if __name__ == "__main__":
    main()

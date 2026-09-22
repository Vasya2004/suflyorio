#!/usr/bin/env python3
"""Generate the 1024x1024 App Icon (no alpha) for Suflyor.

Renders with Pillow instead of AppKit: AppKit's NSGraphicsContext needs a
display connection and silently produces a blank/black bitmap when run
headless (e.g. from a script on a Mac with no active window server),
which is why the old make_icon.swift generated an all-black PNG.
"""
import sys
from PIL import Image, ImageDraw

SS = 4
SIZE = 1024 * SS


def generate() -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE), "#000000")
    draw = ImageDraw.Draw(img)

    top = (18, 92, 68)
    bottom = (8, 28, 24)
    for y in range(SIZE):
        t = y / SIZE
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        draw.line([(0, y), (SIZE, y)], fill=(r, g, b))

    frame_w = int(SIZE * 0.56)
    frame_h = int(frame_w * 1.35)
    frame_x0 = (SIZE - frame_w) // 2
    frame_y0 = (SIZE - frame_h) // 2 - int(SIZE * 0.02)
    frame_x1 = frame_x0 + frame_w
    frame_y1 = frame_y0 + frame_h
    radius = int(SIZE * 0.075)

    draw.rounded_rectangle(
        [frame_x0, frame_y0, frame_x1, frame_y1], radius=radius,
        fill=(15, 56, 44), outline=(235, 245, 240), width=int(SIZE * 0.011),
    )

    line_color = (255, 255, 255)
    line_h = int(SIZE * 0.034)
    gap = int(SIZE * 0.050)
    widths = [0.62, 0.78, 0.50, 0.70, 0.40]
    cx = (frame_x0 + frame_x1) // 2
    start_y = frame_y0 + int(frame_h * 0.17)
    for i, wfrac in enumerate(widths):
        lw = int(frame_w * wfrac * 0.8)
        y0 = start_y + i * gap
        y1 = y0 + line_h
        x0 = cx - lw // 2
        x1 = cx + lw // 2
        alpha_fade = 1.0 - (i * 0.05)
        col = tuple(int(c * alpha_fade) for c in line_color)
        draw.rounded_rectangle([x0, y0, x1, y1], radius=line_h // 2, fill=col)

    dot_r = int(SIZE * 0.055)
    dot_cx = cx
    dot_cy = frame_y1 - int(SIZE * 0.16)
    ring_pad = int(SIZE * 0.010)
    draw.ellipse(
        [dot_cx - dot_r - ring_pad, dot_cy - dot_r - ring_pad,
         dot_cx + dot_r + ring_pad, dot_cy + dot_r + ring_pad],
        fill=(245, 250, 248),
    )
    draw.ellipse(
        [dot_cx - dot_r, dot_cy - dot_r, dot_cx + dot_r, dot_cy + dot_r],
        fill=(255, 61, 45),
    )

    return img.resize((1024, 1024), Image.LANCZOS)


if __name__ == "__main__":
    output = sys.argv[1] if len(sys.argv) > 1 else "Sufler/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    generate().save(output)
    print(f"Wrote {output}")

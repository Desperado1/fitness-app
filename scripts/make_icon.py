#!/usr/bin/env python3
"""Generate the FlowFit app icon: bold FF initials with an accent dot
on the charcoal base. Writes 1024x1024 PNG into the AppIcon asset."""

from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
CHARCOAL = (0x12, 0x12, 0x14)
OFF_WHITE = (0xF5, 0xF5, 0xF4)
ACCENT = (0x64, 0xB5, 0xC9)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

img = Image.new("RGB", (SIZE, SIZE), CHARCOAL)
draw = ImageDraw.Draw(img)

font = ImageFont.truetype(FONT, 430)
text = "FF"
left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
text_w, text_h = right - left, bottom - top

dot_r = 46
gap = 26
total_w = text_w + gap + dot_r * 2
x = (SIZE - total_w) / 2 - left
y = (SIZE - text_h) / 2 - top

draw.text((x, y), text, font=font, fill=OFF_WHITE)

# Accent dot sitting on the baseline after the initials.
dot_cx = x + left + text_w + gap + dot_r
dot_cy = y + top + text_h - dot_r
draw.ellipse(
    (dot_cx - dot_r, dot_cy - dot_r, dot_cx + dot_r, dot_cy + dot_r),
    fill=ACCENT,
)

out = "FlowFit/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
img.save(out)
print(f"wrote {out}")

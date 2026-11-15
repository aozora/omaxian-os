#!/usr/bin/env python3
"""Illustrations for the installer's file-manager page (packagechooser).
Drawn from scratch (no upstream artwork): a stylised file-manager window
with the app name.  gen-fm-chooser-images.py <outdir>"""
import sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1]
BG = (11, 15, 20)
PANEL = (22, 28, 36)
LINE = (40, 48, 60)
TEXT = (230, 236, 240)
DIM = (140, 150, 160)
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

def card(name, tagline, accent, style, path):
    W, H = 640, 400
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    # window
    x0, y0, x1, y1 = 40, 40, W - 40, H - 100
    d.rounded_rectangle((x0, y0, x1, y1), 12, fill=PANEL, outline=LINE, width=2)
    d.rectangle((x0 + 2, y0 + 2, x1 - 2, y0 + 34), fill=(30, 37, 47))
    d.rounded_rectangle((x0 + 60, y0 + 9, x1 - 60, y0 + 27), 6, fill=BG)
    if style == "sidebar":  # Strata: places sidebar + list rows
        d.rectangle((x0 + 2, y0 + 36, x0 + 150, y1 - 2), fill=(18, 23, 30))
        for i in range(6):
            yy = y0 + 54 + i * 30
            d.rounded_rectangle((x0 + 16, yy, x0 + 30, yy + 14), 3, fill=accent if i == 0 else LINE)
            d.rounded_rectangle((x0 + 40, yy + 3, x0 + 130, yy + 11), 4, fill=DIM if i == 0 else LINE)
        for i in range(7):
            yy = y0 + 50 + i * 28
            if i == 1:
                d.rectangle((x0 + 152, yy - 6, x1 - 2, yy + 20), fill=(accent[0] // 4, accent[1] // 4, accent[2] // 4))
            d.rounded_rectangle((x0 + 166, yy, x0 + 182, yy + 14), 3, fill=accent)
            d.rounded_rectangle((x0 + 194, yy + 3, x0 + 330 - (i % 3) * 30, yy + 11), 4, fill=TEXT if i == 1 else DIM)
            d.rounded_rectangle((x1 - 120, yy + 3, x1 - 30, yy + 11), 4, fill=LINE)
    else:  # Folio: icon grid
        for r in range(2):
            for c in range(5):
                cx = x0 + 40 + c * 105
                cy = y0 + 56 + r * 100
                sel = (r, c) == (0, 1)
                if sel:
                    d.rounded_rectangle((cx - 12, cy - 8, cx + 76, cy + 86), 8, fill=(accent[0] // 4, accent[1] // 4, accent[2] // 4))
                d.rounded_rectangle((cx + 6, cy, cx + 58, cy + 10), 3, fill=accent)
                d.rounded_rectangle((cx, cy + 6, cx + 64, cy + 52), 6, fill=accent)
                d.rounded_rectangle((cx + 6, cy + 64, cx + 58, cy + 72), 4, fill=TEXT if sel else DIM)
    fb = ImageFont.truetype(BOLD, 34)
    fs = ImageFont.truetype(SANS, 17)
    d.text((40, H - 86), name, font=fb, fill=TEXT)
    d.text((40, H - 40), tagline, font=fs, fill=DIM)
    d.rectangle((40, H - 46, 40 + d.textlength(name, font=fb), H - 44), fill=accent)
    im.save(path, optimize=True)

card("Strata", "GTK 4 file manager \u2014 Omaxian's default", (63, 208, 192), "sidebar", f"{OUT}/fm-strata.png")
card("Folio", "Omarchy's Qt Quick file manager (community app)", (229, 160, 76), "grid", f"{OUT}/fm-folio.png")

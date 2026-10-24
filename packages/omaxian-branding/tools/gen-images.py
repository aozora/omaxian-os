#!/usr/bin/env python3
"""Derived raster assets: blurred/dimmed backgrounds, progress bar, selection box."""
import sys
from PIL import Image, ImageFilter, ImageEnhance, ImageDraw
wall, br, ply, grubt, cal = sys.argv[1:6]
ACCENT = (63, 208, 192, 255)
BG = (11, 15, 20, 255)

w = Image.open(wall).convert("RGB")
# GRUB: dimmed wallpaper, 1920x1080 (GRUB scales it with stretch)
g = ImageEnhance.Brightness(w.resize((1920, 1080))).enhance(0.45)
g.save(f"{grubt}/background.png")
# LightDM greeter: blurred+dimmed wallpaper
l = ImageEnhance.Brightness(w.filter(ImageFilter.GaussianBlur(6))).enhance(0.7)
l.save(f"{br}/greeter-background.png")

# GRUB selection highlight (9-slice: select_c/n/s/e/w/...: we use one center tile)
for name, col in (("select_c", (63, 208, 192, 70)),):
    Image.new("RGBA", (8, 8), col).save(f"{grubt}/{name}.png")
for side in ("n", "s", "e", "w", "ne", "nw", "se", "sw"):
    Image.new("RGBA", (2, 2), (63, 208, 192, 160)).save(f"{grubt}/select_{side}.png")
logo = Image.open(f"{br}/omaxian-logo-128.png").convert("RGBA")
logo.save(f"{grubt}/logo.png")

# Plymouth: logo + progress bar pieces
Image.open(f"{br}/omaxian-logo-256.png").save(f"{ply}/logo.png")
Image.open(f"{br}/omaxian-wordmark.png").save(f"{ply}/wordmark.png")
Image.new("RGBA", (320, 4), (255, 255, 255, 40)).save(f"{ply}/progress-bg.png")
Image.new("RGBA", (320, 4), ACCENT).save(f"{ply}/progress-fg.png")
box = Image.new("RGBA", (360, 40), (0, 0, 0, 0))
ImageDraw.Draw(box).rounded_rectangle((0, 0, 359, 39), 8, fill=(255, 255, 255, 30), outline=ACCENT)
box.save(f"{ply}/entry.png")
Image.new("RGBA", (10, 10), (234, 255, 251, 255)).save(f"{ply}/bullet.png")

# Calamares
Image.open(f"{br}/omaxian-logo-128.png").save(f"{cal}/logo.png")
Image.open(f"{br}/omaxian-logo-64.png").save(f"{cal}/icon.png")
welcome = Image.new("RGBA", (640, 200), BG)
wm = Image.open(f"{br}/omaxian-wordmark.png").convert("RGBA")
welcome.alpha_composite(wm, ((640 - wm.width) // 2, (200 - wm.height) // 2))
welcome.save(f"{cal}/welcome.png")
sl = ImageEnhance.Brightness(w.resize((800, 450))).enhance(0.8).convert("RGBA")
sl.alpha_composite(wm.resize((wm.width * 2 // 3, wm.height * 2 // 3)), (40, 330))
sl.save(f"{cal}/slide1.png")

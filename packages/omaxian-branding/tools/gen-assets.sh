#!/bin/bash
# Render Omaxian OS branding assets from the Omaxian logos/wallpapers.
#   gen-assets.sh <omaxian-src-dir> <out-root>
# Produces under <out-root>: usr/share/plymouth/themes/omaxian/*,
# usr/share/grub/themes/omaxian/*, usr/share/backgrounds/omaxian/*,
# usr/share/calamares/branding/omaxian/*, usr/share/omaxian/branding/*
set -euo pipefail
SRC=$1; OUT=$2
HERE="$(cd "$(dirname "$0")" && pwd)"
LOGOS="$SRC/omaxian-logos"; WALL="$SRC/omaxian-wallpapers"
need() { command -v "$1" >/dev/null || { echo "missing build tool: $1" >&2; exit 1; }; }
need rsvg-convert; need grub-mkfont; need python3
PLY="$OUT/usr/share/plymouth/themes/omaxian"
GRUBT="$OUT/usr/share/grub/themes/omaxian"
BG="$OUT/usr/share/backgrounds/omaxian"
CAL="$OUT/usr/share/calamares/branding/omaxian"
BR="$OUT/usr/share/omaxian/branding"
mkdir -p "$PLY" "$GRUBT" "$BG" "$CAL" "$BR"

# logos
rsvg-convert -w 256 "$LOGOS/logo-2-ox-monogram.svg" -o "$BR/omaxian-logo-256.png"
rsvg-convert -w 128 "$LOGOS/logo-2-ox-monogram.svg" -o "$BR/omaxian-logo-128.png"
rsvg-convert -w 64  "$LOGOS/logo-2-ox-monogram.svg" -o "$BR/omaxian-logo-64.png"
rsvg-convert -w 640 "$LOGOS/logo-3-wordmark-x.svg"  -o "$BR/omaxian-wordmark.png"
cp "$LOGOS/logo-2-ox-monogram.svg" "$BR/omaxian-logo.svg"
cp "$LOGOS/logo-5-app-tile.svg" "$BR/omaxian-tile.svg"

# wallpapers (text-free variants for the desktop, branded for greeter/grub)
for res in 1920x1080 2560x1440 3840x2160; do
	[ -d "$WALL/$res" ] && cp "$WALL/$res"/*.png "$BG/" || true
done
[ -d "$WALL/no-text/1920x1080" ] && for f in "$WALL"/no-text/1920x1080/*.png; do cp "$f" "$BG/notext-$(basename "$f")"; done
DEFAULT_WP=$(ls "$BG"/wallpaper-v1-nebula-ridge-1920x1080.png 2>/dev/null || ls "$BG"/*.png | head -1)
ln -sf "$(basename "$DEFAULT_WP")" "$BG/default.png"

python3 "$HERE/gen-images.py" "$DEFAULT_WP" "$BR" "$PLY" "$GRUBT" "$CAL"

# GRUB fonts (.pf2)
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
FONTB=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
JB="$SRC/omaxian/.local/share/fonts/JetBrains-Mono-Nerd-Font-Complete.ttf"
[ -f "$JB" ] && FONT="$JB" && FONTB="$JB"
grub-mkfont -s 16 -n "Omaxian Regular 16" -o "$GRUBT/omaxian-16.pf2" "$FONT"
grub-mkfont -s 24 -n "Omaxian Bold 24" -o "$GRUBT/omaxian-24.pf2" "$FONTB"
cp "$HERE/../files-static/grub-theme.txt" "$GRUBT/theme.txt"
cp "$HERE/../files-static/omaxian.plymouth" "$HERE/../files-static/omaxian.script" "$PLY/"
cp "$HERE/../files-static/calamares/"* "$CAL/"
echo "branding assets rendered into $OUT"

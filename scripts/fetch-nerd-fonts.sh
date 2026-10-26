#!/bin/bash
# Download the pinned JetBrainsMono.tar.xz from the official Nerd Fonts GitHub
# release, verify it against NERD_FONTS_JBM_SHA256 (config/build.conf) and
# against the release's SHA-256.txt, then extract the selected variants'
# TTFs + OFL.txt + README.md into $1. Downloads are cached in
# $BUILDDIR/dl/nerd-fonts-<ver>/ (gitignored); a pre-seeded copy in
# $PAYLOADDIR/fonts/ is used for fully offline builds.
#   fetch-nerd-fonts.sh <outdir>
set -euo pipefail
. "$(dirname "$0")/../config/build.conf"
OUT=${1:?outdir}
VER=$NERD_FONTS_VERSION; WANT=$NERD_FONTS_JBM_SHA256
A=JetBrainsMono.tar.xz
BASE="https://github.com/$NERD_FONTS_REPO/releases/download/v$VER"
DL="$BUILDDIR/dl/nerd-fonts-$VER"; mkdir -p "$DL" "$OUT"
[[ $WANT =~ ^[0-9a-f]{64}$ ]] || { echo "!! NERD_FONTS_JBM_SHA256 is not a sha256" >&2; exit 1; }
if [ ! -s "$DL/$A" ] && [ -s "$PAYLOADDIR/fonts/nerd-fonts-$VER-$A" ]; then
	cp "$PAYLOADDIR/fonts/nerd-fonts-$VER-$A" "$DL/$A"
fi
if [ ! -s "$DL/$A" ]; then
	curl --fail --location --silent --show-error --max-filesize $((64*1024*1024)) -o "$DL/$A.part" "$BASE/$A"
	mv "$DL/$A.part" "$DL/$A"
fi
sha=$(sha256sum "$DL/$A" | sed 's/ .*//')
[ "$sha" = "$WANT" ] || { echo "!! $A sha256 mismatch: got $sha, pinned $WANT" >&2; rm -f "$DL/$A"; exit 1; }
# cross-check with upstream's SHA-256.txt when reachable/cached (informative;
# the pin above is authoritative)
if [ -s "$DL/SHA-256.txt" ] || curl --fail --location --silent --max-filesize 1048576 -o "$DL/SHA-256.txt" "$BASE/SHA-256.txt" 2>/dev/null; then
	up=$(awk -v a="$A" '$2==a{print $1}' "$DL/SHA-256.txt")
	[ -z "$up" ] || [ "$up" = "$WANT" ] || { echo "!! upstream SHA-256.txt lists $up for $A (pinned $WANT)" >&2; exit 1; }
fi
echo ":: $A v$VER sha256 OK ($sha)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
tar -xJf "$DL/$A" -C "$TMP"
rm -rf "${OUT:?}"/*; mkdir -p "$OUT/ttf"
n=0
for v in $NERD_FONTS_JBM_VARIANTS; do
	[[ $v =~ ^[A-Za-z]+$ ]] || { echo "!! bad variant '$v'" >&2; exit 1; }
	for f in "$TMP"/JetBrainsMono"$v"-*.ttf; do
		[ -e "$f" ] || { echo "!! variant $v not in $A" >&2; exit 1; }
		install -m 0644 "$f" "$OUT/ttf/"; n=$((n+1))
	done
done
install -m 0644 "$TMP/OFL.txt" "$TMP/README.md" "$OUT/"
echo "$VER" > "$OUT/.version"; echo "$sha" > "$OUT/.sha256"
echo ":: $n TTFs ($NERD_FONTS_JBM_VARIANTS) -> $OUT/ttf"

#!/bin/bash
# Download the pinned ydotool source (GitHub archive of tag v$YDOTOOL_VERSION),
# check its sha256 (config/build.conf) and extract it into $1.
#   fetch-ydotool.sh <outdir>
# YDOTOOL_COMMIT is recorded in the package and cross-checked against the tag
# when the network allows (git ls-remote); the sha256 is the hard check.
set -euo pipefail
. "$(dirname "$0")/../config/build.conf"
OUT=${1:?outdir}
V=$YDOTOOL_VERSION
DL="$BUILDDIR/dl/ydotool"; F="$DL/ydotool-$V.tar.gz"; mkdir -p "$DL"
if [ ! -s "$F" ]; then
	curl --fail --location --silent --show-error --max-filesize 10485760 -o "$F.part" \
		"https://github.com/$YDOTOOL_REPO/archive/refs/tags/v$V.tar.gz"
	mv "$F.part" "$F"
fi
sha=$(sha256sum "$F" | cut -d' ' -f1)
[ "$sha" = "$YDOTOOL_SRC_SHA256" ] || { echo "!! ydotool-$V.tar.gz sha256 $sha != pinned $YDOTOOL_SRC_SHA256" >&2; exit 1; }
echo ":: ydotool-$V.tar.gz sha256 OK ($sha)"
if c=$(timeout 20 git ls-remote "https://github.com/$YDOTOOL_REPO" "refs/tags/v$V" 2>/dev/null | cut -f1) && [ -n "$c" ]; then
	[ "$c" = "$YDOTOOL_COMMIT" ] || { echo "!! tag v$V now points to $c, pinned $YDOTOOL_COMMIT" >&2; exit 1; }
	echo ":: tag v$V = $c"
else
	echo ":: (offline: tag commit not re-checked; sha256 pinned)"
fi
rm -rf "$OUT"; mkdir -p "$OUT"
tar -xzf "$F" -C "$OUT" --strip-components=1
echo "$V" > "$OUT/.version"; echo "$YDOTOOL_COMMIT" > "$OUT/.commit"; echo "$sha" > "$OUT/.sha256"

#!/bin/bash
# Speed-up for slow/serial mirrors: resolve the full package set inside the
# chroot (apt --print-uris) and download the .debs in parallel with curl
# straight into the chroot's apt cache. Optionally seed from an old cache dir.
#   prefetch-debs.sh <rootfs> <list-dir> [seed-cache-dir]
set -euo pipefail
R=$1; L=$2; SEED=${3:-}
TOP="$(cd "$(dirname "$0")/.." && pwd)"
A="$R/var/cache/apt/archives"; mkdir -p "$A/partial"
if [ -n "$SEED" ] && [ -d "$SEED" ]; then cp -n "$SEED"/*.deb "$A/" 2>/dev/null || true; fi
PK=$(cd "$L" && grep -hvE '^\s*(#|$)' 00-base.list 10-xlibre.list 20-audio.list 30-desktop.list 40-user.list 50-omaxian.list 90-live.list | sed 's/#.*//' | tr -s ' \t' '\n' | grep -v '^$' | tr '\n' ' ')
"$TOP/scripts/chroot-run.sh" "$R" apt-get -qq --print-uris install $PK > "$R/tmp/uris" || true
UP=${PREFETCH_UPSTREAM:-https://packages.devuan.org/merged}
awk '{gsub(/\x27/,"",$1); print $1, $2}' "$R/tmp/uris" | grep '\.deb' | while read -r url file; do
	[ -s "$A/$file" ] && continue
	echo "$(echo "$url" | sed "s#^http://127.0.0.1:8099/merged#$UP#") $file"
done > "$R/tmp/todo"
echo ":: prefetch: $(wc -l < "$R/tmp/todo") debs to download ($(wc -l < "$R/tmp/uris") total)"
xargs -P 8 -n 2 sh -c 'curl -fsSL --retry 4 -o "'"$A"'/partial/$1" "$0" && mv "'"$A"'/partial/$1" "'"$A"'/$1" || echo "!! $0"' < "$R/tmp/todo"
rm -f "$R/tmp/uris" "$R/tmp/todo"

#!/bin/bash
# Download the pinned upstream VoxType .deb (GitHub release) and verify it:
#  1. sha256 == VOXTYPE_DEB_SHA256 (config/build.conf)
#  2. its detached signature (.deb.asc) verifies with the pinned release key
#     (config/upstream-keys/voxtype-release.asc) made by VOXTYPE_SIGNING_FPR
#  3. the signed SHA256SUMS.txt verifies with the same key, and the CPU
#     binaries inside the .deb match the sums it lists (SHA256SUMS.txt does
#     not list the .deb itself).
# Cache: $BUILDDIR/dl/voxtype-<ver>/ (gitignored); offline seed:
# $PAYLOADDIR/voxtype/ (same file names). Copies the verified .deb to $1
# (no outdir: verify the cache only).
#   fetch-voxtype.sh [outdir]
set -euo pipefail
TOPDIR=$(cd "$(dirname "$0")/.." && pwd)
. "$TOPDIR/config/build.conf"
OUT=${1:-}
V=$VOXTYPE_VERSION; DEB="voxtype_${V}-${VOXTYPE_DEB_REV}_amd64.deb"
BASE="https://github.com/$VOXTYPE_REPO/releases/download/v$V"
DL="$BUILDDIR/dl/voxtype-$V"; KEY="$TOPDIR/config/upstream-keys/voxtype-release.asc"
mkdir -p "$DL"
[[ $VOXTYPE_DEB_SHA256 =~ ^[0-9a-f]{64}$ ]] || { echo "!! VOXTYPE_DEB_SHA256 is not a sha256" >&2; exit 1; }
[[ $VOXTYPE_SIGNING_FPR =~ ^[0-9A-F]{40}$ ]] || { echo "!! VOXTYPE_SIGNING_FPR is not a fingerprint" >&2; exit 1; }
get() { # file maxbytes
	[ -s "$DL/$1" ] && return 0
	if [ -s "$PAYLOADDIR/voxtype/$1" ]; then cp "$PAYLOADDIR/voxtype/$1" "$DL/$1"; return 0; fi
	curl --fail --location --silent --show-error --retry 3 --max-filesize "$2" -o "$DL/$1.part" "$BASE/$1"
	mv "$DL/$1.part" "$DL/$1"
}
get "$DEB" $((512*1024*1024)); get "$DEB.asc" 65536; get SHA256SUMS.txt 1048576; get SHA256SUMS.txt.asc 65536
sha=$(sha256sum "$DL/$DEB" | sed 's/ .*//')
[ "$sha" = "$VOXTYPE_DEB_SHA256" ] || { echo "!! $DEB sha256 mismatch: got $sha, pinned $VOXTYPE_DEB_SHA256" >&2; rm -f "$DL/$DEB"; exit 1; }
G=$(mktemp -d); trap 'rm -rf "$G"' EXIT
gpg --homedir "$G" --batch --quiet --import "$KEY" 2>/dev/null
sigok() { # file sig -> the VALIDSIG primary fingerprint must be the pinned one
	gpg --homedir "$G" --batch --status-fd 1 --verify "$2" "$1" 2>/dev/null \
		| awk -v f="$VOXTYPE_SIGNING_FPR" '$2=="VALIDSIG" && ($3==f || $NF==f){ok=1} END{exit !ok}'
}
sigok "$DL/$DEB" "$DL/$DEB.asc" || { echo "!! $DEB: bad or missing signature by $VOXTYPE_SIGNING_FPR" >&2; exit 1; }
sigok "$DL/SHA256SUMS.txt" "$DL/SHA256SUMS.txt.asc" || { echo "!! SHA256SUMS.txt: bad signature" >&2; rm -f "$DL"/SHA256SUMS.txt*; exit 1; }
for b in avx2 baseline; do
	want=$(awk -v a="voxtype-$V-linux-x86_64-$b" '$2==a{print $1}' "$DL/SHA256SUMS.txt")
	[ -n "$want" ] || { echo "!! SHA256SUMS.txt has no entry for voxtype-$V-linux-x86_64-$b" >&2; exit 1; }
	got=$(dpkg-deb --fsys-tarfile "$DL/$DEB" | tar -xO "./usr/lib/voxtype/voxtype-$b" | sha256sum | sed 's/ .*//')
	[ "$got" = "$want" ] || { echo "!! voxtype-$b inside $DEB does not match the signed SHA256SUMS.txt" >&2; exit 1; }
done
[ "$(dpkg-deb -f "$DL/$DEB" Version)" = "$V-$VOXTYPE_DEB_REV" ] || { echo "!! $DEB: unexpected Version field" >&2; exit 1; }
[ -z "$OUT" ] || { mkdir -p "$OUT"; install -m 0644 "$DL/$DEB" "$OUT/"; }
echo ":: $DEB sha256 OK ($sha), signature OK ($VOXTYPE_SIGNING_FPR), binaries match signed SHA256SUMS.txt${OUT:+ -> $OUT}"

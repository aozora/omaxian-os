#!/bin/bash
# Pinned upstream bits that are not in Devuan Excalibur:
#   chezmoi .deb and MyGo Music .deb -> $OUTDIR/debs (local apt repo)
#   rustic binary tarball -> $1 (package upstream dir)
#   typecase git archive -> $2 (package upstream dir)
# Checksums live in config/build.conf.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
RUSTIC_OUT=${1:-}
TYPECASE_OUT=${2:-}
DL="$BUILDDIR/dl/third-party"
mkdir -p "$DL" "$OUTDIR/debs"
fetch() { # url dest sha256
	local url=$1 dest=$2 sha=$3
	if [ -f "$dest" ] && echo "$sha  $dest" | sha256sum -c --status; then
		return 0
	fi
	msg "download ${url##*/}"
	curl -fL --retry 3 --retry-delay 2 -o "$dest.part" "$url"
	mv "$dest.part" "$dest"
	echo "$sha  $dest" | sha256sum -c --status || die "sha256 mismatch: $dest"
}
fetch "https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux_amd64.deb" \
	"$DL/chezmoi_${CHEZMOI_VERSION}_amd64.deb" "$CHEZMOI_DEB_SHA256"
fetch "https://github.com/egoist/mygo-music/releases/download/v${MYGO_VERSION}/mygo-music_${MYGO_VERSION}_amd64.deb" \
	"$DL/mygo-music_${MYGO_VERSION}_amd64.deb" "$MYGO_DEB_SHA256"
cp -a "$DL/chezmoi_${CHEZMOI_VERSION}_amd64.deb" "$DL/mygo-music_${MYGO_VERSION}_amd64.deb" "$OUTDIR/debs/"
if [ -n "$RUSTIC_OUT" ]; then
	fetch "https://github.com/rustic-rs/rustic/releases/download/v${RUSTIC_VERSION}/rustic-v${RUSTIC_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
		"$DL/rustic-v${RUSTIC_VERSION}.tar.gz" "$RUSTIC_TARBALL_SHA256"
	rm -rf "$RUSTIC_OUT"; mkdir -p "$RUSTIC_OUT"
	tar -xzf "$DL/rustic-v${RUSTIC_VERSION}.tar.gz" -C "$RUSTIC_OUT" rustic
	[ -f "$RUSTIC_OUT/rustic" ] || die "rustic tarball has no rustic binary"
	chmod 755 "$RUSTIC_OUT/rustic"
	echo "$RUSTIC_VERSION" > "$RUSTIC_OUT/.version"
fi
if [ -n "$TYPECASE_OUT" ]; then
	fetch "https://github.com/iretonsean/typecase/archive/${TYPECASE_COMMIT}.tar.gz" \
		"$DL/typecase-${TYPECASE_COMMIT}.tar.gz" "$TYPECASE_SHA256"
	rm -rf "$TYPECASE_OUT"; mkdir -p "$TYPECASE_OUT"
	tar -xzf "$DL/typecase-${TYPECASE_COMMIT}.tar.gz" -C "$TYPECASE_OUT" --strip-components=1
	[ -f "$TYPECASE_OUT/typecase.py" ] || die "typecase archive has no typecase.py"
	chmod 755 "$TYPECASE_OUT/typecase"
	echo "$TYPECASE_COMMIT" > "$TYPECASE_OUT/.commit"
fi
msg "third-party pins ok (chezmoi $CHEZMOI_VERSION, rustic $RUSTIC_VERSION, mygo-music $MYGO_VERSION, typecase ${TYPECASE_COMMIT:0:12})"

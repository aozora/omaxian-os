#!/bin/bash
# Debian trixie chroot for community-app install and the two source builds.
# Pinned binaries and QML are built for Qt 6.8 (Excalibur). An Ubuntu image
# host does not have libqt6core6t64, so build-community-apps.sh enters here.
#   ensure-build-chroot.sh <omaxian-src>
set -euo pipefail
. "$(dirname "$0")/lib.sh"
SRC=$(realpath "${1:?omaxian src}")
CHROOT=${OMAXIAN_TRIXIE_CHROOT:-/var/lib/omaxian-trixie}
[ "$(id -u)" -eq 0 ] || die "ensure-build-chroot needs root"
need mmdebstrap python3 curl gpg
[ -d "$SRC/community-apps" ] || die "no community-apps in $SRC"
mapfile -t pkgs < <(python3 - "$SRC" <<'PY'
import json, os, sys
src = sys.argv[1]
want = {"ca-certificates", "curl", "git", "jq", "python3", "file", "binutils", "xz-utils"}
apps = os.path.join(src, "community-apps")
for name in os.listdir(apps):
    p = os.path.join(apps, name, "omaxian.deps.json")
    if not os.path.isfile(p):
        continue
    d = json.load(open(p))
    want.update(d.get("apt") or [])
for w in sorted(want):
    print(w)
PY
)
key=$(printf '%s\n' "${pkgs[@]}" | sha256sum | cut -c1-16)
if [ ! -x "$CHROOT/usr/bin/apt-get" ]; then
	msg "trixie chroot: creating $CHROOT (${#pkgs[@]} packages, no Recommends)"
	rm -rf "$CHROOT"
	# Ubuntu's debian-archive-keyring lags the current trixie signing keys.
	KEYRING="$BUILDDIR/keyring/debian-archive-trixie.gpg"
	mkdir -p "$BUILDDIR/keyring"
	if [ ! -s "$KEYRING" ]; then
		tmp=$(mktemp)
		curl -fsSL https://ftp-master.debian.org/keys/archive-key-13.asc | gpg --dearmor > "$tmp"
		curl -fsSL https://ftp-master.debian.org/keys/archive-key-13-security.asc | gpg --dearmor >> "$tmp"
		mv "$tmp" "$KEYRING"
	fi
	# apt inside mmdebstrap reads the keyring as the unprivileged _apt user.
	chmod 644 "$KEYRING"
	inc=$(IFS=,; echo "${pkgs[*]}")
	mmdebstrap --mode=root --variant=apt --arch=amd64 \
		--keyring="$KEYRING" \
		--aptopt='Apt::Install-Recommends "false"' \
		--include="$inc" trixie "$CHROOT" \
		"deb http://deb.debian.org/debian trixie main"
	echo "$key" > "$CHROOT/.omaxian-pkgkey"
fi
if [ "$(cat "$CHROOT/.omaxian-pkgkey" 2>/dev/null || true)" != "$key" ]; then
	msg "trixie chroot: installing community-app packages"
	chroot "$CHROOT" apt-get update
	chroot "$CHROOT" env DEBIAN_FRONTEND=noninteractive \
		apt-get install -y --no-install-recommends "${pkgs[@]}"
	echo "$key" > "$CHROOT/.omaxian-pkgkey"
fi
msg "trixie chroot ready ($CHROOT, pkgkey $key)"

#!/bin/bash
# Mirror the XLibre packages Omaxian uses into the local reprepro repo, so
# apt.omaxian.org does not depend on a single third-party maintainer.
# Verifies the upstream Release signature with config/apt/keys/NexusSfan.pgp.
# (Optional; the shipped image uses the upstream xlibre-debian repo directly.)
. "$(dirname "$0")/lib.sh"
need curl gpgv reprepro
U="${XLIBRE_URI%/}"; D="$BUILDDIR/xlibre-mirror"; mkdir -p "$D"
curl -fsSL "$U/dists/$XLIBRE_SUITE/InRelease" -o "$D/InRelease"
gpgv --keyring "$TOPDIR/config/apt/keys/NexusSfan.pgp" "$D/InRelease" || die "xlibre InRelease signature invalid"
curl -fsSL "$U/dists/$XLIBRE_SUITE/$XLIBRE_COMPONENT/binary-$ARCH/Packages.gz" | gzip -dc > "$D/Packages"
want=$(grep -oE '^Packages.gz$' /dev/null; awk '/^Package:/{print $2}' "$D/Packages" | grep -E '^(xlibre|xserver-xlibre|x11proto)' | sort -u)
for p in $want; do
	f=$(awk -v p="$p" '$1=="Package:"{c=($2==p)} c&&$1=="Filename:"{print $2}' "$D/Packages" | tail -1)
	s=$(awk -v p="$p" '$1=="Package:"{c=($2==p)} c&&$1=="SHA256:"{print $2}' "$D/Packages" | tail -1)
	[ -s "$D/$(basename "$f")" ] || curl -fsSL "$U/$f" -o "$D/$(basename "$f")"
	echo "$s  $D/$(basename "$f")" | sha256sum -c --quiet || die "checksum mismatch for $p"
	reprepro -b "$LOCALREPO" includedeb "$OMAXIAN_APT_SUITE" "$D/$(basename "$f")" || true
done
msg "xlibre packages mirrored into $LOCALREPO"

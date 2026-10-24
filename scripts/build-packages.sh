#!/bin/bash
# Build the Omaxian OS .debs into $OUTDIR/debs.
#   build-packages.sh [pkg ...]   (default: all)
# Packages are staged in $BUILDDIR/pkg/<name> so generated/vendored content
# never lands in the git tree.
. "$(dirname "$0")/lib.sh"
need dpkg-buildpackage dh rsvg-convert grub-mkfont python3 curl jq
ALL="omaxian-base omaxian-branding omaxian-session omaxian-strata omaxian-firstboot omaxian-calamares-settings"
PKGS=${*:-$ALL}
STAGE="$BUILDDIR/pkg"; DEBS="$OUTDIR/debs"; mkdir -p "$STAGE" "$DEBS"
OMX="$BUILDDIR/src/omaxian"
cp_tree() { mkdir -p "$2"; cp -a "$1/." "$2/"; }

prep_omaxian-base() {
	local d=$1 f=$1/files
	mkdir -p "$f/etc/apt/preferences.d" "$f/etc/apt/apt.conf.d" "$f/usr/share/keyrings"
	cp "$TOPDIR"/config/apt/preferences.d/*.pref "$f/etc/apt/preferences.d/"
	cp "$TOPDIR"/config/apt/apt.conf.d/* "$f/etc/apt/apt.conf.d/"
	[ -f "$TOPDIR/keys/public/omaxian-archive-keyring.pgp" ] || "$TOPDIR/scripts/gen-test-key.sh"
	cp "$TOPDIR/keys/public/omaxian-archive-keyring.pgp" "$f/usr/share/keyrings/"
	cat > "$f/etc/omaxian-release" <<EOR
NAME="Omaxian OS"
VERSION="$OMAXIAN_VERSION ($OMAXIAN_CODENAME)"
VERSION_ID="$OMAXIAN_VERSION"
BASE="Devuan $DEVUAN_SUITE"
OMAXIAN_SHELL="$OMAXIAN_SHELL_REF"
HOME_URL="https://omaxian.org"
EOR
}
prep_omaxian-branding() {
	[ -d "$OMX" ] || "$TOPDIR/scripts/fetch-omaxian.sh"
	bash "$1/tools/gen-assets.sh" "$OMX" "$1/assets"
	sed -i "s/@VERSION@/$OMAXIAN_VERSION/g" "$1"/assets/usr/share/calamares/branding/omaxian/branding.desc
}
prep_omaxian-session() {
	local d=$1
	[ -d "$OMX/omarchy-quattro/themes" ] || "$TOPDIR/scripts/fetch-omaxian.sh"
	mkdir -p "$d/vendor/src"
	# runtime pieces of the Omaxian repo (omarchy-quattro is only needed to
	# render the home template; its themes are already inside it)
	for x in scripts omaxian packaging version LICENSE README.md; do cp -a "$OMX/$x" "$d/vendor/src/"; done
	bash "$TOPDIR/scripts/gen-home-template.sh" "$OMX" "$d/vendor/home-template"
	cp "$OMX/packaging/sysvinit/power-profiles-daemon" "$d/debian/omaxian-session.power-profiles-daemon.init"
	sed -i "1s/([^)]*)/($(cat "$OMX/version" 2>/dev/null | tr -d 'v\n' || echo 1.0.3)-1)/" "$d/debian/changelog" || true
}
prep_omaxian-strata() {
	"$TOPDIR/scripts/fetch-strata.sh" "$1/upstream"
}
prep_omaxian-firstboot() {
	mkdir -p "$1/files/usr/share/omaxian"
	cp "$TOPDIR/config/flatpaks.list" "$TOPDIR/config/appimages.manifest" "$1/files/usr/share/omaxian/"
}
prep_omaxian-calamares-settings() { :; }

for p in $PKGS; do
	msg "== $p"
	rm -rf "${STAGE:?}/$p"; mkdir -p "$STAGE/$p"
	cp_tree "$TOPDIR/packages/$p" "$STAGE/$p/$p"
	"prep_$p" "$STAGE/$p/$p"
	( cd "$STAGE/$p/$p" && dpkg-buildpackage -b -us -uc -d > "$STAGE/$p/build.log" 2>&1 ) \
		|| { tail -40 "$STAGE/$p/build.log"; die "$p failed (log: $STAGE/$p/build.log)"; }
	for deb in "$STAGE/$p"/*.deb; do rm -f "$DEBS/$(basename "$deb" | cut -d_ -f1)"_*.deb; done
	cp "$STAGE/$p"/*.deb "$DEBS/"
	ls -1 "$STAGE/$p"/*.deb | sed 's/^/   /'
done
msg "debs in $DEBS"

#!/bin/bash
# Build the Omaxian OS .debs into $OUTDIR/debs.
#   build-packages.sh [pkg ...]   (default: all)
# Packages are staged in $BUILDDIR/pkg/<name> so generated/vendored content
# never lands in the git tree.
. "$(dirname "$0")/lib.sh"
need dpkg-buildpackage dh rsvg-convert grub-mkfont python3 curl jq
ALL="omaxian-base omaxian-branding omaxian-fonts-nerd omaxian-session omaxian-strata omaxian-firstboot omaxian-calamares-settings omaxian-voxtype"
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
VERSION_CODENAME="$OMAXIAN_CODENAME_ID"
CODENAME="$OMAXIAN_CODENAME"
BASE="Devuan $DEVUAN_SUITE"
OMAXIAN_SHELL="$OMAXIAN_SHELL_REF"
HOME_URL="https://omaxian.org"
EOR
	# os-release branding; base-files' copy is diverted by omaxian-base.preinst
	local vid=${OMAXIAN_VERSION//\~/-}
	mkdir -p "$f/usr/lib"
	cat > "$f/usr/lib/os-release" <<EOR
PRETTY_NAME="Omaxian OS $OMAXIAN_VERSION ($OMAXIAN_CODENAME)"
NAME="Omaxian OS"
VERSION_ID="$vid"
VERSION="$OMAXIAN_VERSION ($OMAXIAN_CODENAME)"
VERSION_CODENAME="$OMAXIAN_CODENAME_ID"
# apt uses its sources.list, not os-release; tools that need the base
# release read these (cf. UBUNTU_CODENAME on Ubuntu derivatives).
DEVUAN_CODENAME="$DEVUAN_SUITE"
DEBIAN_CODENAME="trixie"
ID=omaxian
ID_LIKE="devuan debian"
HOME_URL="https://omaxian.org/"
SUPPORT_URL="https://omaxian.org/support"
BUG_REPORT_URL="https://github.com/aozora/omaxian/issues"
LOGO=omaxian
EOR
}
prep_omaxian-branding() {
	[ -d "$OMX" ] || "$TOPDIR/scripts/fetch-omaxian.sh"
	bash "$1/tools/gen-assets.sh" "$OMX" "$1/assets"
	sed -i -e "s/@VERSION@/$OMAXIAN_VERSION/g" -e "s/@CODENAME@/$OMAXIAN_CODENAME/g" \
		"$1"/assets/usr/share/calamares/branding/omaxian/branding.desc \
		"$1"/assets/usr/share/plymouth/themes/omaxian/omaxian.script \
		"$1"/assets/usr/share/grub/themes/omaxian/theme.txt
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
	# upstream version from the Omaxian checkout, Debian revision from our changelog
	local up rev; up=$(cat "$OMX/version" 2>/dev/null | tr -d 'v\n'); up=${up:-1.0.4}
	rev=$(sed -n '1s/.*(\([^)]*\)).*/\1/p' "$d/debian/changelog"); rev=${rev##*-}
	sed -i "1s/([^)]*)/($up-${rev:-2})/" "$d/debian/changelog" || true
}
prep_omaxian-fonts-nerd() {
	"$TOPDIR/scripts/fetch-nerd-fonts.sh" "$1/upstream"
	local v; v=$(sed -n '1s/.*(\([^-)]*\).*/\1/p' "$1/debian/changelog")
	[ "$v" = "$NERD_FONTS_VERSION" ] || die "omaxian-fonts-nerd changelog ($v) != NERD_FONTS_VERSION ($NERD_FONTS_VERSION)"
}
prep_omaxian-strata() {
	local v; v=$(sed -n '1s/.*(\([^-)]*\).*/\1/p' "$1/debian/changelog")
	[ "$v" = "$STRATA_VERSION" ] || die "omaxian-strata changelog ($v) != STRATA_VERSION ($STRATA_VERSION)"
	"$TOPDIR/scripts/fetch-strata.sh" "$1/upstream"
}
prep_omaxian-firstboot() {
	mkdir -p "$1/files/usr/share/omaxian"
	cp "$TOPDIR/config/flatpaks.list" "$TOPDIR/config/appimages.manifest" "$1/files/usr/share/omaxian/"
	bash "$TOPDIR/scripts/gen-netinstall.sh" --optional-flatpaks "$TOPDIR/config/optional-groups.list" \
		"$1/files/usr/share/omaxian/optional-flatpaks.list"
}
prep_omaxian-calamares-settings() {
	bash "$TOPDIR/scripts/gen-netinstall.sh" "$TOPDIR/config/optional-groups.list" "$1/files/etc/calamares/modules/netinstall.conf" \
		--appimages "$TOPDIR/config/appimages.manifest"
}
prep_omaxian-voxtype() { # integration only; the upstream .deb is fetched by build-rootfs (full)
	local v; v=$(sed -n '1s/.*(\([^-)]*\).*/\1/p' "$1/debian/changelog")
	[ "$v" = "$VOXTYPE_VERSION" ] || die "omaxian-voxtype changelog ($v) != VOXTYPE_VERSION ($VOXTYPE_VERSION)"
}

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

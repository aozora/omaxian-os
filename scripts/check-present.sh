#!/bin/bash
# Fail the rootfs build if must-have paths or packages did not land.
# Style: LCOS live-build hooks 0110–0114 (grub-install, icon/theme, greeter, apps).
#
#   check-present.sh <rootfs> [base|full]
#
# Flavor defaults to "full" when <rootfs>/var/lib/omaxian/full-offline exists,
# otherwise "base". Prints every missing item, then exits non-zero.
# File checks are enough for a hermetic test root; package checks run only
# when <rootfs>/var/lib/dpkg/status is present.
set -euo pipefail

usage() { echo "usage: $0 <rootfs> [base|full]" >&2; exit 2; }
[ $# -ge 1 ] || usage
R=$1
[ -d "$R" ] || { echo "xx check-present: not a directory: $R" >&2; exit 2; }

if [ -n "${2:-}" ]; then
	FLAVOR=$2
else
	if [ -e "$R/var/lib/omaxian/full-offline" ]; then FLAVOR=full; else FLAVOR=base; fi
fi
case $FLAVOR in base|full) ;; *) echo "xx check-present: flavor must be base or full (got $FLAVOR)" >&2; exit 2 ;; esac

# Every community app seeded into the home template (0.3). Same set as
# tools/diag/r19/media/common.sh. omarchy-local-ai is an engine with no
# .desktop (the live checks report DESKTOP_SKIP).
APPS="aether cards checkmate disktree fantasi flowtunes folio hype monologue omacalc omacut omarchy-local-ai omarchy-meeting-recorder omareel omaview omawrite plain signed"

missing=()
# miss <id> [detail]
miss() { local n=$1; shift; missing+=("$n${*:+ ($*)}"); }

is_exec() { [ -f "$1" ] && [ -x "$1" ]; }

# executable file (follows a symlink that resolves under the rootfs)
want_exec() {
	local rel=$1 id=${2:-$1}
	if is_exec "$R$rel"; then return 0; fi
	# usrmerge: /sbin -> usr/sbin (relative). [ -x "$R/sbin/init" ] works when
	# the symlink is well-formed; also accept the /usr/sbin twin.
	case $rel in
		/sbin/*) is_exec "$R/usr$rel" && return 0 ;;
		/usr/sbin/*) is_exec "$R/${rel#/usr}" && return 0 ;;
	esac
	miss "$id" "missing or not executable"
}

want_file() {
	local rel=$1 id=${2:-$1}
	[ -f "$R$rel" ] || miss "$id" "missing file"
}

want_dir() {
	local rel=$1 id=${2:-$1}
	[ -d "$R$rel" ] || miss "$id" "missing directory"
}

# want_grep <rel> <ere> <id>
want_grep() {
	local rel=$1 ere=$2 id=$3
	if [ ! -f "$R$rel" ]; then miss "$id" "missing file $rel"; return 0; fi
	grep -Eq "$ere" "$R$rel" || miss "$id" "no match /$ere/ in $rel"
}

# want_any_glob <glob-under-root> <id>  — at least one match
want_any_glob() {
	local glob=$1 id=$2 m
	# Manifest globs are case-insensitive (see config/appimages.manifest).
	m=$(shopt -s nocaseglob nullglob
		# shellcheck disable=SC2086
		set -- $R$glob
		if [ $# -eq 1 ] && [ ! -e "$1" ]; then exit 0; fi
		printf "%s\n" "$@")
	[ -n "$m" ] || miss "$id" "no file matches $glob"
}

want_pkg() {
	local p=$1
	[ -f "$R/var/lib/dpkg/status" ] || return 0
	local st
	st=$(dpkg-query --admindir="$R/var/lib/dpkg" -W -f '${db:Status-Status}' "$p" 2>/dev/null || true)
	[ "$st" = installed ] || miss "package $p" "status=${st:-not-installed}"
}

# --- bootloader (config/package-lists/00-base.list: grub2-common, grub-pc-bin,
# grub-efi-amd64-bin). Paths from those Debian/Devuan packages; LCOS 0110
# checks grub-install + /usr/lib/grub/i386-pc.
want_exec /usr/sbin/grub-install
want_dir  /usr/lib/grub/i386-pc
want_file /usr/lib/grub/i386-pc/normal.mod
want_dir  /usr/lib/grub/x86_64-efi
want_file /usr/lib/grub/x86_64-efi/normal.mod
want_file /usr/share/grub/themes/omaxian/theme.txt
want_file /usr/share/omaxian/grub/quirks.cfg
want_pkg  grub2-common
want_pkg  grub-pc-bin
want_pkg  grub-efi-amd64-bin

# --- Plymouth theme (omaxian-branding; set as default in s_configure)
want_file /usr/share/plymouth/themes/omaxian/omaxian.plymouth
want_file /usr/share/plymouth/themes/omaxian/omaxian.script
want_pkg  plymouth
want_pkg  omaxian-branding
ply_ok=0
if [ -f "$R/etc/plymouth/plymouthd.conf" ] && grep -Eq '^[[:space:]]*Theme[[:space:]]*=[[:space:]]*omaxian[[:space:]]*$' "$R/etc/plymouth/plymouthd.conf"; then
	ply_ok=1
fi
if [ -e "$R/usr/share/plymouth/themes/default.plymouth" ]; then
	# file, symlink, or alternative: the path or contents must name omaxian
	if grep -Fq '/usr/share/plymouth/themes/omaxian' "$R/usr/share/plymouth/themes/default.plymouth" 2>/dev/null \
		|| grep -Eq 'Name=Omaxian|Theme=omaxian' "$R/usr/share/plymouth/themes/default.plymouth" 2>/dev/null \
		|| readlink "$R/usr/share/plymouth/themes/default.plymouth" 2>/dev/null | grep -Fq omaxian; then
		ply_ok=1
	fi
fi
[ "$ply_ok" = 1 ] || miss "plymouth default theme" "Theme=omaxian not set in plymouthd.conf or default.plymouth"

# --- LightDM + Omaxian greeter (30-desktop.list + omaxian-branding)
want_exec /usr/sbin/lightdm
want_exec /usr/sbin/lightdm-gtk-greeter
want_file /etc/lightdm/lightdm.conf.d/50-omaxian.conf
want_grep /etc/lightdm/lightdm.conf.d/50-omaxian.conf '^greeter-session=lightdm-gtk-greeter' \
	"lightdm greeter-session"
want_grep /etc/lightdm/lightdm.conf.d/50-omaxian.conf '^user-session=omaxian' \
	"lightdm user-session"
want_file /etc/lightdm/lightdm-gtk-greeter.conf-omaxian
want_pkg  lightdm
want_pkg  lightdm-gtk-greeter

# --- Quickshell (Debian/Devuan package ships both names) and the Omaxian
# session / shell tree (omaxian-session 1.2.4-2).
want_exec /usr/bin/qs
want_exec /usr/bin/quickshell
want_exec /usr/bin/omaxian-session
want_file /usr/share/xsessions/omaxian.desktop
want_grep /usr/share/xsessions/omaxian.desktop '^Exec=/usr/bin/omaxian-session' \
	"omaxian.desktop Exec"
want_file /usr/share/omaxian/home-template/.local/share/omarchy/shell/shell.qml
want_file /usr/share/omaxian/home-template/.local/share/omarchy/version
want_exec /usr/bin/i3
want_pkg  quickshell
want_pkg  omaxian-session
want_pkg  i3-wm

# --- Strata, ydotool (omaxian-strata, omaxian-ydotool debs)
want_exec /usr/bin/strata
want_exec /usr/bin/ydotool
want_exec /usr/bin/ydotoold
want_pkg  omaxian-strata
want_pkg  omaxian-ydotool

# --- init, PipeWire, XLibre, fonts, installer stack (all live ISOs)
if is_exec "$R/sbin/init" || is_exec "$R/usr/sbin/init"; then
	:
else
	miss "/sbin/init" "missing or not executable"
fi
want_exec /usr/bin/pipewire
want_file /usr/share/fonts/truetype/jetbrains-mono-nerd/JetBrainsMonoNerdFont-Regular.ttf
want_exec /usr/bin/calamares
want_exec /usr/bin/omaxian-install
want_exec /usr/libexec/omaxian/keep-manual
want_pkg  sysvinit-core
want_pkg  eudev
want_pkg  pipewire
want_pkg  xserver-xlibre-core
want_pkg  omaxian-base
want_pkg  omaxian-fonts-nerd
want_pkg  omaxian-calamares-settings
want_pkg  calamares

# --- class "base" AppImages (s_payload copies these into both ISOs)
# shellcheck source=../config/build.conf
TOP=${TOPDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
MANIFEST=$TOP/config/appimages.manifest
if [ -f "$MANIFEST" ]; then
	want_dir /usr/share/omaxian/payload/appimages
	while IFS=$'\t' read -r id glob _method _source class _rest || [ -n "${id:-}" ]; do
		[[ -z ${id:-} || $id == \#* ]] && continue
		[ "${class:-}" = base ] || continue
		want_any_glob "/usr/share/omaxian/payload/appimages/$glob" "payload AppImage $id (class base)"
	done < "$MANIFEST"
fi

# --- community apps in the home template (both flavors, omaxian-session)
for a in $APPS; do
	want_exec "/usr/share/omaxian/home-template/.local/bin/$a"
	# omarchy-local-ai is an engine: the session seeds the binary and leaves
	# it off the menu (no .desktop).
	[ "$a" = omarchy-local-ai ] && continue
	want_any_glob "/usr/share/omaxian/home-template/.local/share/applications/*${a}*.desktop" \
		"desktop entry for $a"
done

# --- full ISO only (s_full_from_base)
if [ "$FLAVOR" = full ]; then
	want_file /var/lib/omaxian/full-offline
	want_file /var/cache/omaxian/optional-pool/Packages
	want_any_glob "/var/cache/omaxian/optional-pool/voxtype_*.deb" "optional-pool voxtype .deb"
	want_any_glob "/var/cache/omaxian/optional-pool/omaxian-voxtype_*.deb" "optional-pool omaxian-voxtype .deb"
fi

if [ ${#missing[@]} -gt 0 ]; then
	echo "xx check-present: $FLAVOR rootfs is missing ${#missing[@]} required item(s):" >&2
	for i in "${missing[@]}"; do
		echo "   - $i" >&2
	done
	exit 1
fi
echo ":: check-present: $FLAVOR rootfs has every required path/package" >&2
exit 0

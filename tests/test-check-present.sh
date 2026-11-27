#!/bin/bash
# Hermetic tests for scripts/check-present.sh: a fake root with every required
# path must pass; removing one path must fail and name it; full-only items
# are not required on base.
set -u
cd "$(dirname "$0")/.." || exit
pass=0; fail=0
ok() { echo "ok   $*"; pass=$((pass+1)); }
bad() { echo "FAIL $*"; fail=$((fail+1)); }

CHK=scripts/check-present.sh
bash -n "$CHK" && ok "bash -n check-present.sh" || bad "bash -n check-present.sh"

# Minimal "installed" stanza for dpkg-query --admindir
pkg_st() { printf 'Package: %s\nStatus: install ok installed\nVersion: 1\n\n' "$1"; }

# Plant every path check-present.sh requires for the given flavor.
# $1 = dest root
populate() {
	local R=$1 flavor=${2:-base}
	mkdir -p "$R/var/lib/dpkg/updates" "$R/var/lib/dpkg/info" "$R/var/lib/dpkg/triggers"
	: > "$R/var/lib/dpkg/available"
	: > "$R/var/lib/dpkg/status"
	install_bin() { mkdir -p "$R$(dirname "$1")"; printf '#!/bin/sh\nexit 0\n' > "$R$1"; chmod +x "$R$1"; }
	install_f() { mkdir -p "$R$(dirname "$1")"; echo "${2:-x}" > "$R$1"; }
	install_bin /usr/sbin/grub-install
	install_f /usr/lib/grub/i386-pc/normal.mod
	install_f /usr/lib/grub/x86_64-efi/normal.mod
	install_f /usr/share/grub/themes/omaxian/theme.txt
	install_f /usr/share/omaxian/grub/quirks.cfg
	install_f /usr/share/plymouth/themes/omaxian/omaxian.plymouth
	install_f /usr/share/plymouth/themes/omaxian/omaxian.script
	install_f /etc/plymouth/plymouthd.conf $' [Daemon]\nTheme=omaxian\n'
	# Theme= line must be at the start of the line (see the check's ERE)
	printf 'Theme=omaxian\n' > "$R/etc/plymouth/plymouthd.conf"
	install_bin /usr/sbin/lightdm
	install_bin /usr/sbin/lightdm-gtk-greeter
	install_f /etc/lightdm/lightdm.conf.d/50-omaxian.conf $'greeter-session=lightdm-gtk-greeter\nuser-session=omaxian\n'
	install_f /etc/lightdm/lightdm-gtk-greeter.conf-omaxian
	install_bin /usr/bin/qs
	install_bin /usr/bin/quickshell
	install_bin /usr/bin/omaxian-session
	install_f /usr/share/xsessions/omaxian.desktop $'Exec=/usr/bin/omaxian-session\n'
	install_f /usr/share/omaxian/home-template/.local/share/omarchy/shell/shell.qml
	install_f /usr/share/omaxian/home-template/.local/share/omarchy/version v1.2.4
	install_bin /usr/bin/i3
	install_bin /usr/bin/strata
	install_bin /usr/bin/ydotool
	install_bin /usr/bin/ydotoold
	install_bin /sbin/init
	install_bin /usr/bin/pipewire
	install_f /usr/share/fonts/truetype/jetbrains-mono-nerd/JetBrainsMonoNerdFont-Regular.ttf
	install_bin /usr/bin/calamares
	install_bin /usr/bin/omaxian-install
	install_bin /usr/libexec/omaxian/keep-manual
	install_f /usr/share/omaxian/payload/appimages/DesktopEditors-x86_64.AppImage
	local a
	for a in aether cards checkmate disktree fantasi flowtunes folio hype monologue omacalc omacut omarchy-local-ai omarchy-meeting-recorder omareel omaview omawrite plain signed; do
		install_bin /usr/share/omaxian/home-template/.local/bin/$a
		install_f /usr/share/omaxian/home-template/.local/share/applications/${a}.desktop
	done
	if [ "$flavor" = full ]; then
		install_f /var/lib/omaxian/full-offline
		install_f /var/cache/omaxian/optional-pool/Packages
		install_f /var/cache/omaxian/optional-pool/voxtype_1.1.1-1_amd64.deb
		install_f /var/cache/omaxian/optional-pool/omaxian-voxtype_1.1.1-3_all.deb
	fi
	local p
	for p in grub2-common grub-pc-bin grub-efi-amd64-bin plymouth omaxian-branding \
		lightdm lightdm-gtk-greeter quickshell omaxian-session i3-wm \
		omaxian-strata omaxian-ydotool sysvinit-core eudev pipewire \
		xserver-xlibre-core omaxian-base omaxian-fonts-nerd \
		omaxian-calamares-settings calamares; do
		pkg_st "$p" >> "$R/var/lib/dpkg/status"
	done
}

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

populate "$T/base" base
if bash "$CHK" "$T/base" base >"$T/base.out" 2>"$T/base.err"; then
	ok "populated base root passes"
else
	bad "populated base root failed: $(cat "$T/base.err")"
fi

# full-only paths must not be required on base
if grep -q 'optional-pool\|full-offline' "$T/base.err"; then
	bad "base check mentioned full-only paths"
else
	ok "base check does not require full-only paths"
fi

populate "$T/full" full
if bash "$CHK" "$T/full" full >"$T/full.out" 2>"$T/full.err"; then
	ok "populated full root passes"
else
	bad "populated full root failed: $(cat "$T/full.err")"
fi

# auto-detect flavor from the full-offline marker
if bash "$CHK" "$T/full" >"$T/auto.out" 2>"$T/auto.err"; then
	ok "flavor defaults to full when full-offline exists"
else
	bad "auto flavor failed: $(cat "$T/auto.err")"
fi

# missing grub-install is named and fails
rm -f "$T/base/usr/sbin/grub-install"
if bash "$CHK" "$T/base" base >"$T/miss.out" 2>"$T/miss.err"; then
	bad "check passed after removing grub-install"
else
	grep -Fq '/usr/sbin/grub-install' "$T/miss.err" \
		&& ok "missing grub-install is named in the error" \
		|| bad "error did not name grub-install: $(cat "$T/miss.err")"
fi

# restore grub-install, drop a BIOS GRUB module
install -D /dev/null "$T/base/usr/sbin/grub-install"; chmod +x "$T/base/usr/sbin/grub-install"
rm -f "$T/base/usr/lib/grub/i386-pc/normal.mod"
if bash "$CHK" "$T/base" base >"$T/mod.out" 2>"$T/mod.err"; then
	bad "check passed after removing i386-pc/normal.mod"
else
	grep -Fq '/usr/lib/grub/i386-pc/normal.mod' "$T/mod.err" \
		&& ok "missing BIOS GRUB module is named" \
		|| bad "error did not name i386-pc/normal.mod: $(cat "$T/mod.err")"
fi

# qs missing
install -D /dev/null "$T/base/usr/lib/grub/i386-pc/normal.mod"
rm -f "$T/base/usr/bin/qs"
if bash "$CHK" "$T/base" base >"$T/qs.out" 2>"$T/qs.err"; then
	bad "check passed after removing qs"
else
	grep -Fq '/usr/bin/qs' "$T/qs.err" \
		&& ok "missing qs is named" \
		|| bad "error did not name qs: $(cat "$T/qs.err")"
fi

# full flavor without the optional pool fails, and says so
populate "$T/full2" base
# no full-offline / pool
if bash "$CHK" "$T/full2" full >"$T/ff.out" 2>"$T/ff.err"; then
	bad "full check passed without optional pool"
else
	grep -q 'optional-pool\|full-offline' "$T/ff.err" \
		&& ok "full check reports missing pool / full-offline" \
		|| bad "full error was unclear: $(cat "$T/ff.err")"
fi

# wrong greeter session
populate "$T/g" base
printf 'greeter-session=something-else\nuser-session=omaxian\n' > "$T/g/etc/lightdm/lightdm.conf.d/50-omaxian.conf"
if bash "$CHK" "$T/g" base >"$T/g.out" 2>"$T/g.err"; then
	bad "check passed with a wrong greeter-session"
else
	grep -q 'greeter-session' "$T/g.err" \
		&& ok "wrong greeter-session is reported" \
		|| bad "error did not mention greeter-session: $(cat "$T/g.err")"
fi

# missing package in dpkg status
populate "$T/p2" base
python3 - "$T/p2/var/lib/dpkg/status" <<'PY'
import sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
parts = text.split("\n\n")
keep = [p for p in parts if not p.startswith("Package: quickshell\n")]
pathlib.Path(sys.argv[1]).write_text("\n\n".join(keep).rstrip()+"\n")
PY
if bash "$CHK" "$T/p2" base >"$T/pk.out" 2>"$T/pk.err"; then
	bad "check passed with quickshell not installed in dpkg"
else
	grep -q 'package quickshell' "$T/pk.err" \
		&& ok "missing dpkg package quickshell is named" \
		|| bad "error did not name package quickshell: $(cat "$T/pk.err")"
fi

echo "== $pass passed, $fail failed"
[ "$fail" = 0 ]

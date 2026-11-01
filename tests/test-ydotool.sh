#!/bin/bash
# omaxian-ydotool: built deb contents + per-user seeding (symlink, i3 line).
cd "$(dirname "$0")/.."; P=packages/omaxian-ydotool/files; n=0; f=0
ok() { echo "ok   $*"; n=$((n+1)); }; ko() { echo "FAIL $*"; f=$((f+1)); }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
grep -qx 'KERNEL=="uinput", GROUP="input", MODE="0660"' $P/usr/lib/udev/rules.d/60-omaxian-uinput.rules && ok "udev rule" || ko "udev rule"
grep -qx uinput $P/etc/modules-load.d/omaxian-uinput.conf && ok "uinput in modules-load.d" || ko "modules-load.d"
grep -A3 '^- sudo\|^  *- sudo' packages/omaxian-calamares-settings/files/etc/calamares/modules/users.conf | grep -q 'name: input' && ok "installer adds users to input" || ko "users.conf input"
grep -q 'LIVE_USER_DEFAULT_GROUPS=.* input"' scripts/build-rootfs.sh && ok "live user in input" || ko "live user groups"
mkdir -p "$W/h/.config/i3/config.d"
HOME=$W/h $P/usr/libexec/omaxian/ydotool-seed
[ "$(readlink "$W/h/.local/bin/ydotoold")" = /usr/bin/ydotoold ] && ok "~/.local/bin/ydotoold -> /usr/bin/ydotoold" || ko "symlink"
grep -qx 'exec --no-startup-id ~/.local/bin/ydotoold' "$W/h/.config/i3/config.d/50-ydotool.conf" && ok "i3 autostart line (exact)" || ko "i3 line"
rm "$W/h/.config/i3/config.d/50-ydotool.conf"; HOME=$W/h $P/usr/libexec/omaxian/ydotool-seed
[ ! -e "$W/h/.config/i3/config.d/50-ydotool.conf" ] && ok "deleted fragment not re-created" || ko "re-created"
mkdir -p "$W/n"; HOME=$W/n $P/usr/libexec/omaxian/ydotool-seed; [ ! -e "$W/n/.local/state/omaxian/ydotool-seeded" ] && ok "waits for the i3 config.d (home seeding)" || ko "seeded without config.d"
D=$(ls out/debs/omaxian-ydotool_*_amd64.deb 2>/dev/null | tail -1)
if [ -n "$D" ]; then
	c=$(dpkg-deb -c "$D")
	for x in ./usr/bin/ydotool ./usr/bin/ydotoold ./usr/lib/udev/rules.d/60-omaxian-uinput.rules ./etc/modules-load.d/omaxian-uinput.conf ./etc/X11/Xsession.d/36omaxian-ydotool; do grep -q " $x\$" <<<"$c" && ok "deb: $x" || ko "deb: $x"; done
	! grep -q systemd <<<"$c" && ok "deb: no systemd unit" || ko "systemd unit shipped"
	dpkg-deb -f "$D" Conflicts | grep -qw ydotool && ok "deb: conflicts/replaces Debian ydotool" || ko "conflicts"
	dpkg-deb -x "$D" "$W/x" && [ "$("$W/x/usr/bin/ydotoold" --version)" = v1.0.4 ] && ok "ydotoold --version v1.0.4" || ko "version"
fi
echo "--- $n passed, $f failed"; [ $f = 0 ]

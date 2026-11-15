# Shared checks for 0.2 "Space Cat" VM tests (sourced by live.sh / check.sh).
# Needs $U (user) and $H (home). Lines are PASS/FAIL markers for the serial log.
APPS="disktree folio monologue omacalc omacut omarchy-meeting-recorder omawrite plain signed"
c_versions() {
	uname -r; cat /proc/cmdline
	dpkg-query -W eudev linux-image-amd64 omaxian-base omaxian-branding omaxian-firstboot omaxian-session omaxian-strata 'pipewire:amd64' quickshell sysvinit-core 2>&1
	grep -E '^(PRETTY_NAME|VERSION|VERSION_CODENAME)=' /etc/os-release
	strata --version 2>&1 | head -1
}
c_noxfce() {
	local x; x=$(dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' 'xfce4*' 'thunar*' 'libxfce4ui*' 'xfdesktop*' 'xfwm4*' 'mousepad' 'ristretto' 2>/dev/null | awk '$1=="ii"{print $2}' | tr '\n' ' ')
	echo "XFCE_INSTALLED: [$x]"
	local bad; bad=$(echo "$x" | tr ' ' '\n' | grep -vxE 'xfce4-power-manager|xfce4-power-manager-data|libxfce4ui-2-0|libxfce4ui-common|libxfce4util7|libxfce4util-common|' )
	[ -z "$bad" ] && echo NOXFCE_PASS || echo "NOXFCE_FAIL $bad"
	for p in xfce4-power-manager xfconf; do dpkg-query -W -f '${db:Status-Abbrev}' $p 2>/dev/null | grep -q '^ii' && echo "DEP_PASS $p" || echo "DEP_FAIL $p"; done
	command -v thunar >/dev/null && echo THUNAR_FAIL || echo NOTHUNAR_PASS
	ls /usr/share/xsessions/
	ls /usr/share/xsessions/ | grep -qi xfce && echo XSESSION_NOXFCE_FAIL || echo XSESSION_NOXFCE_PASS
	command -v xfconf-query >/dev/null && echo XFCONF_QUERY_PASS || echo XFCONF_QUERY_FAIL
}
c_apps() {
	local a b d
	for a in $APPS; do
		b=$H/.local/bin/$a
		[ -x "$b" ] && echo "EXEC_PASS $a" || { echo "EXEC_FAIL $a"; continue; }
		file -L "$b" 2>/dev/null | grep -q ELF && { ldd "$b" 2>&1 | grep -q 'not found' && echo "LDD_FAIL $a $(ldd "$b" | grep 'not found' | head -3 | tr '\n' ' ')" || echo "LDD_PASS $a"; } || echo "LDD_PASS $a (script)"
		d=$(grep -l "$a" $H/.local/share/applications/*.desktop 2>/dev/null | head -1)
		[ -n "$d" ] && echo "DESKTOP_PASS $a" || echo "DESKTOP_FAIL $a"
	done
	timeout 10 su - $U -c "$H/.local/bin/disktree --version" >/dev/null 2>&1 || timeout 10 su - $U -c "$H/.local/bin/disktree --help" >/dev/null 2>&1 && echo "CLI_PASS disktree" || echo "CLI_FAIL disktree"
	timeout 10 su - $U -c "$H/.local/bin/signed --help" >/dev/null 2>&1 && echo "CLI_PASS signed" || echo "CLI_FAIL signed"
	for a in folio monologue omacalc omacut omawrite plain; do
		timeout 12 su - $U -c "QT_QPA_PLATFORM=offscreen $H/.local/bin/$a" >/tmp/qml-$a.log 2>&1; rc=$?
		# 124 = still running after 12 s (window up, no QML error) -> launch OK
		if [ $rc = 124 ] && ! grep -qiE 'qrc:.*error|is not a type|module .* not installed|cannot load' /tmp/qml-$a.log; then echo "QML_PASS $a"; else echo "QML_FAIL $a rc=$rc $(tail -3 /tmp/qml-$a.log | tr '\n' ' ')"; fi
	done
}
c_user() {
	id $U; id -nG $U | grep -qw input && echo INPUT_PASS || echo INPUT_FAIL
	ls -l /dev/uinput; su - $U -c 'test -w /dev/uinput' && echo UINPUT_WRITABLE_PASS || echo UINPUT_WRITABLE_FAIL
	pgrep -u $U -af ydotoold && echo YDOTOOLD_PASS || echo YDOTOOLD_FAIL
	pgrep -u $U -x quickshell >/dev/null || pgrep -u $U -f 'qs ' >/dev/null && echo QUICKSHELL_PASS || echo QUICKSHELL_FAIL
	for d in Desktop Documents Downloads Music Pictures Videos Templates Public; do [ -d $H/$d ] && echo "XDG_PASS $d" || echo "XDG_FAIL $d"; done
	local f=$H/.config/onlyoffice/DesktopEditors.conf
	echo "--- $f"; cat $f; stat -c '%U:%G %a' $f $H/.config/onlyoffice
	grep -qx '\[General\]' $f && grep -qx 'titlebar=system' $f && [ "$(stat -c %U $f)" = $U ] && [ "$(stat -c %U $H/.config/onlyoffice)" = $U ] && echo ONLYOFFICE_CONF_PASS || echo ONLYOFFICE_CONF_FAIL
	echo "--- mimeapps"; cat $H/.config/mimeapps.list 2>/dev/null; stat -c %U $H/.config/mimeapps.list 2>/dev/null
	echo "FM_SYSTEM: $(cat /etc/omaxian/file-manager 2>/dev/null || echo none)"
	echo "XDG_MIME_DEFAULT: $(su - $U -c 'xdg-mime query default inode/directory')"
}
c_system() {
	for s in omaxian-thermald omaxian-iio-sensor-proxy omaxian-switcheroo-control omaxian-bolt chrony open-vm-tools; do
		ls /etc/rc2.d/ | grep -q "S..$s\$" && echo "RC_PASS $s" || echo "RC_FAIL $s"; /etc/init.d/$s status 2>&1 | tail -1
	done
	sysctl kernel.unprivileged_bpf_disabled net.core.bpf_jit_harden
	ls /etc/default/grub.d/ /usr/share/omaxian/grub/ 2>&1
	[ -e /etc/grub.d/05_omaxian_quirks ] && echo GRUB_QUIRKS_SCRIPT_PASS || echo GRUB_QUIRKS_SCRIPT_MISSING
	grep -q "omaxian_quirks" /boot/grub/grub.cfg 2>/dev/null && echo GRUB_QUIRKS_IN_CFG || echo GRUB_QUIRKS_NOT_IN_CFG
	grep -rqs 'Proxy' /etc/apt/apt.conf.d/ && echo APT_CONFIG_FAIL_proxy_left || echo APT_CONFIG_PASS
	[ -z "$(dpkg --audit 2>&1)" ] && echo DPKG_AUDIT_PASS || echo DPKG_AUDIT_FAIL
	echo "DPKG_RC_COUNT $(dpkg -l | grep -c '^rc')"
	dmesg 2>/dev/null | grep -iE 'oom|segfault|call trace' | head -5
}

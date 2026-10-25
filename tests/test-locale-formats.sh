#!/bin/bash
# Unit test for calamares-locale-formats (fake target roots, no install).
set -u
cd "$(dirname "$0")/.."
S=packages/omaxian-calamares-settings/files/usr/libexec/omaxian/calamares-locale-formats
ZT=/usr/share/zoneinfo/zone.tab
[ -r $ZT ] || ZT=build/rootfs-base/usr/share/zoneinfo/zone.tab
fail=0
LCS="LC_NUMERIC LC_TIME LC_MONETARY LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION"
mkroot() { # dir lang formats tz tzmode(file|link)
	mkdir -p "$1/etc/default" "$1/usr/share/zoneinfo"; cp $ZT "$1/usr/share/zoneinfo/zone.tab"
	{ echo "LANG=$2"; for k in $LCS; do echo "$k=$3"; done; } > "$1/etc/default/locale"
	cp "$1/etc/default/locale" "$1/etc/locale.conf"
	if [ "$5" = file ]; then echo "$4" > "$1/etc/timezone"; else ln -s "/usr/share/zoneinfo/$4" "$1/etc/localtime"; fi
}
check() { # name lang formats tz mode expected
	d=$(mktemp -d); mkroot "$d" "$2" "$3" "$4" "$5"
	sh $S "$d"
	for f in etc/default/locale etc/locale.conf; do
		got=$(grep -c "^LC_.*=$6\$" "$d/$f"); lang=$(sed -n 's/^LANG=//p' "$d/$f")
		if [ "$got" = 9 ] && [ "$lang" = "$2" ]; then :; else echo "FAIL $1 ($f): $(tr '\n' ' ' < "$d/$f")"; fail=1; fi
	done
	[ $fail = 0 ] && echo "ok   $1"
	rm -rf "$d"
}
check "en_US + Europe/Rome (auto it_IT) -> en_US"      en_US.UTF-8 it_IT.UTF-8 Europe/Rome    file en_US.UTF-8
check "en_US + Europe/Rome via localtime link"         en_US.UTF-8 it_IT.UTF-8 Europe/Rome    link en_US.UTF-8
check "it_IT + Europe/Rome stays it_IT"                it_IT.UTF-8 it_IT.UTF-8 Europe/Rome    file it_IT.UTF-8
check "it_IT + America/New_York (auto en_US) -> it_IT" it_IT.UTF-8 en_US.UTF-8 America/New_York file it_IT.UTF-8
check "en_US + Europe/Rome, explicit en_GB kept"       en_US.UTF-8 en_GB.UTF-8 Europe/Rome    file en_GB.UTF-8
check "en_US + America/New_York unchanged"             en_US.UTF-8 en_US.UTF-8 America/New_York file en_US.UTF-8
# no time zone info: leave the file alone
d=$(mktemp -d); mkdir -p $d/etc/default; printf 'LANG=en_US.UTF-8\nLC_TIME=it_IT.UTF-8\n' > $d/etc/default/locale
sh $S "$d"; grep -q '^LC_TIME=it_IT.UTF-8$' $d/etc/default/locale && echo "ok   no tz -> unchanged" || { echo "FAIL no tz"; fail=1; }; rm -rf "$d"
# Calamares config: the locale/localecfg jobs run before shellprocess@omaxian-post, which calls the fix
C=packages/omaxian-calamares-settings/files
seq=$(sed -n '/^- exec:/,/^- show:/p' $C/etc/calamares/settings.conf)
n() { echo "$seq" | grep -n -- "- $1\$" | cut -d: -f1; }
if [ "$(n localecfg)" -lt "$(n shellprocess@omaxian-post)" ] && grep -q calamares-locale-formats $C/usr/libexec/omaxian/calamares-post; then echo "ok   settings.conf order + calamares-post hook"; else echo "FAIL config order/hook"; fail=1; fi
exit $fail

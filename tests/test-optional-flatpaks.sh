#!/bin/bash
# Optional groups shipped as Flatpaks (Telegram, config/optional-groups.list
# field 6): netinstall.conf entry, the Calamares pick record, omaxianoptional.
# Hermetic (stub libcalamares, no chroot).
set -u
cd "$(dirname "$0")/.."
pass=0; fail=0
ok() { echo "ok   $*"; pass=$((pass+1)); }; bad() { echo "FAIL $*"; fail=$((fail+1)); }
T=$(mktemp -d); trap 'rm -rf $T' EXIT
G=config/optional-groups.list
# 1 Telegram is no longer an apt package of any group
! grep -vE '^\s*(#|$)' $G config/optional-groups-full.list | cut -d'|' -f5 | grep -qw telegram-desktop && ok "telegram-desktop not in the apt groups" || bad "telegram-desktop still an apt package"
grep -q '^chat-telegram|Telegram|[^|]*|true||org.telegram.desktop$' $G && ok "Telegram group: no apt packages, Flatpak org.telegram.desktop, preselected" || bad "Telegram group line"
# 2 apt optional packages: 24 (22 base groups + 2 VoxType)
n=$(grep -hvE '^\s*(#|$)' $G config/optional-groups-full.list | cut -d'|' -f5 | tr ' ' '\n' | grep . | sort -u | wc -l)
[ "$n" = 24 ] && ok "24 optional apt packages" || bad "optional apt packages: $n (want 24)"
# 3 netinstall.conf: the group keeps a recording entry (flatpak + post-install)
bash scripts/gen-netinstall.sh $G $T/ni.conf
python3 - $T/ni.conf <<'PY' && ok "netinstall: Telegram = flatpak + post-install omaxian-optional-flatpak select org.telegram.desktop" || bad "netinstall Telegram entry"
import re,sys
s=open(sys.argv[1]).read()
g=s.split('- name: "Telegram"')[1].split('    - name: "')[0]
assert 'selected: true' in g and 'critical: false' in g
assert re.search(r'packages:\n        - name: flatpak\n          post-install: "/usr/sbin/omaxian-optional-flatpak select org.telegram.desktop"\n', g), g
assert 'telegram-desktop' not in s
PY
n=$(grep -c '^    - name: "' $T/ni.conf); [ "$n" = 6 ] && ok "netinstall: 6 groups (base)" || bad "groups: $n"
# 4 optional-flatpaks.list for omaxian-firstboot / the full build
bash scripts/gen-netinstall.sh --optional-flatpaks $G config/optional-groups-full.list $T/of.list
[ "$(grep -v '^#' $T/of.list)" = "chat-telegram|org.telegram.desktop" ] && ok "optional-flatpaks.list: chat-telegram|org.telegram.desktop" || { bad "optional-flatpaks.list"; cat $T/of.list; }
grep -q 'gen-netinstall.sh" --optional-flatpaks' scripts/build-packages.sh && grep -q 'gen-netinstall.sh" --optional-flatpaks' scripts/build-rootfs.sh \
	&& ok "shipped by omaxian-firstboot, preinstalled by the full build" || bad "build wiring"
# 5 the recording helper (idempotent)
H=packages/omaxian-firstboot/files/usr/sbin/omaxian-optional-flatpak
OMAXIAN_FB_ROOT=$T/r sh $H select org.telegram.desktop && OMAXIAN_FB_ROOT=$T/r sh $H select org.telegram.desktop
[ "$(cat $T/r/var/lib/omaxian/optional-flatpaks.list)" = org.telegram.desktop ] && ok "omaxian-optional-flatpak records once" || bad "helper"
! OMAXIAN_FB_ROOT=$T/r sh $H 2>/dev/null && ok "helper: usage error without args" || bad "helper usage"
# 6 omaxianoptional: the recording entry is not an optional package; record file created
mkdir -p $T/py/libcalamares $T/root
cat > $T/py/libcalamares/__init__.py <<'PY'
import json, os
class _GS:
    def __init__(self): self.d = json.load(open(os.environ["GS"]))
    def value(self, k): return self.d.get(k)
globalstorage = _GS()
class utils:
    @staticmethod
    def warning(m): print("W:", m)
    @staticmethod
    def debug(m): print("D:", m)
PY
for picked in yes no; do
	rm -rf $T/root/var
	if [ $picked = yes ]; then OPS='[{"source":"netinstall@netinstall","try_install":["krita",{"package":"flatpak","pre-script":"","post-script":"/usr/sbin/omaxian-optional-flatpak select org.telegram.desktop"}]}]'
		OMAXIAN_FB_ROOT=$T/root sh $H select org.telegram.desktop
	else OPS='[{"source":"netinstall@netinstall","try_install":["krita"]}]'; fi
	echo "{\"rootMountPoint\":\"$T/root\",\"packageOperations\":$OPS}" > $T/gs.json
	GS=$T/gs.json PYTHONPATH=$T/py python3 - <<'PY' >$T/py.out 2>&1
import importlib.util, subprocess, sys
spec = importlib.util.spec_from_file_location("m", "packages/omaxian-calamares-settings/files/usr/lib/x86_64-linux-gnu/calamares/modules/omaxianoptional/main.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m._installed = lambda root, p: True   # no chroot in the test
real = subprocess.run
m.subprocess.run = lambda a, **k: real(["true"]) if a[0] == "rm" else real(a, **k)
sys.exit(1 if m.run() else 0)
PY
	S=$T/root/var/lib/omaxian
	if [ $picked = yes ]; then
		[ "$(cat $S/optional-packages.list)" = krita ] && [ "$(cat $S/optional-flatpaks.list)" = org.telegram.desktop ] && ok "omaxianoptional, Telegram picked: packages=krita, flatpaks=org.telegram.desktop" || { bad "omaxianoptional picked"; cat $T/py.out; ls -R $S; }
	else
		[ "$(cat $S/optional-packages.list)" = krita ] && [ -f $S/optional-flatpaks.list ] && [ ! -s $S/optional-flatpaks.list ] && ok "omaxianoptional, Telegram not picked: empty flatpak record exists" || { bad "omaxianoptional not picked"; cat $T/py.out; }
	fi
done
echo "$pass passed, $fail failed"; [ $fail = 0 ]

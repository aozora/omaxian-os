#!/bin/bash
# Optional AppImages ("Extra apps (downloaded after install)", manifest class
# "optional"): manifest split, netinstall checkboxes, the Calamares pick
# record, omaxianoptional, omaxian-appimage-fetch (picked only, sha256), and
# the full build's payload filter. Hermetic (stub curl/jq-free, no network).
set -u
cd "$(dirname "$0")/.."
pass=0; fail=0
ok() { echo "ok   $*"; pass=$((pass+1)); }; bad() { echo "FAIL $*"; fail=$((fail+1)); }
T=$(mktemp -d); trap 'rm -rf $T' EXIT
M=config/appimages.manifest
rows() { grep -vE '^\s*(#|$)' $M; }
# 1 manifest: OpenSpot gone; 10 bundled (incl. 3 OpenRA), 6 optional
! grep -qi openspot $M && ok "OpenSpot not in the manifest" || bad "OpenSpot still listed"
b=$(rows | awk -F'\t' '($5==""||$5=="bundled"){print $1}' | sort | tr '\n' ' ')
o=$(rows | awk -F'\t' '$5=="optional"{print $1}' | sort | tr '\n' ' ')
[ "$b" = "bleachbit elecwhat localsend marktext obsidian onlyoffice openra-d2k openra-ra openra-td task_manager_tmog " ] && ok "10 bundled AppImages (3 OpenRA)" || bad "bundled: $b"
[ "$o" = "cursor grok_bot rebased rustdesk shotcut teams_for_linux " ] && ok "6 optional AppImages" || bad "optional: $o"
rows | awk -F'\t' '$5=="optional" && $3=="url" && $6 !~ /^[0-9a-f]{64}$/{bad=1} END{exit bad}' && ok "pinned (url) optional rows carry a sha256" || bad "url rows without sha256"
rows | awk -F'\t' '$5=="optional" && ($3=="payload" || $7==""){bad=1} END{exit bad}' && ok "every optional row has an upstream source and a label" || bad "optional row without source/label"
# 2 netinstall: one unselected group with one unselected checkbox (subgroup) each
bash scripts/gen-netinstall.sh config/optional-groups.list $T/ni.conf config/optional-groups-full.list --appimages $M
python3 - $T/ni.conf <<'PY' && ok "netinstall: 'Extra apps (downloaded after install)', 6 unselected subgroups, curl + omaxian-optional-appimage select <id>" || bad "netinstall extra apps"
import re,sys
s=open(sys.argv[1]).read()
g=s.split('    - name: "Extra apps (downloaded after install)"')[1]
assert '\n    - name: "' not in g, "must be the last group"
assert g.startswith('\n      description:') and '      selected: false\n' in g and '      subgroups:\n' in g
subs=re.findall(r'\n        - name: "([^"]+)"\n          description: "([^"]+)"\n          selected: false\n          critical: false\n          hidden: false\n          packages:\n            - name: curl\n              post-install: "/usr/sbin/omaxian-optional-appimage select ([a-z_]+)"', g)
ids=sorted(x[2] for x in subs)
assert ids==["cursor","grok_bot","rebased","rustdesk","shotcut","teams_for_linux"], subs
assert g.count('- name: "')==6
PY
python3 -c 'import yaml' 2>/dev/null && python3 - $T/ni.conf <<'PY' && ok "netinstall.conf parses as YAML (8 groups on the full ISO)" || bad "yaml"
import sys,yaml
d=yaml.safe_load(open(sys.argv[1]))
assert len(d["groups"])==8 and len(d["groups"][-1]["subgroups"])==6
assert all(s["selected"] is False for s in d["groups"][-1]["subgroups"])
PY
grep -q -- '--appimages "$TOPDIR/config/appimages.manifest"' scripts/build-packages.sh && grep -q -- '--appimages "$TOPDIR/config/appimages.manifest"' scripts/build-rootfs.sh \
	&& ok "build wiring: base (calamares-settings) and full netinstall.conf" || bad "build wiring"
# 3 recording helper
H=packages/omaxian-firstboot/files/usr/sbin/omaxian-optional-appimage
OMAXIAN_FB_ROOT=$T/r sh $H select cursor && OMAXIAN_FB_ROOT=$T/r sh $H select cursor && OMAXIAN_FB_ROOT=$T/r sh $H select shotcut
[ "$(cat $T/r/var/lib/omaxian/optional-appimages.list | tr '\n' ' ')" = "cursor shotcut " ] && ok "omaxian-optional-appimage records each once" || bad "helper"
# 4 omaxianoptional: recording entries are not optional packages; record created
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
OPS='[{"source":"netinstall@netinstall","try_install":["krita",{"package":"curl","pre-script":"","post-script":"/usr/sbin/omaxian-optional-appimage select cursor"}]}]'
echo "{\"rootMountPoint\":\"$T/root\",\"packageOperations\":$OPS}" > $T/gs.json
GS=$T/gs.json PYTHONPATH=$T/py python3 - <<'PY' >$T/py.out 2>&1
import importlib.util, subprocess, sys
spec = importlib.util.spec_from_file_location("m", "packages/omaxian-calamares-settings/files/usr/lib/x86_64-linux-gnu/calamares/modules/omaxianoptional/main.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m._installed = lambda root, p: p != "curl"
real = subprocess.run
m.subprocess.run = lambda a, **k: real(["true"]) if a[0] == "rm" else real(a, **k)
sys.exit(1 if m.run() else 0)
PY
S=$T/root/var/lib/omaxian
[ "$(cat $S/optional-packages.list)" = krita ] && [ ! -s $S/optional-pending.list ] && [ -f $S/optional-appimages.list ] \
	&& ok "omaxianoptional: curl marker not recorded/pending, optional-appimages.list created" || { bad "omaxianoptional"; cat $T/py.out; ls -R $S; }
# 5 omaxian-appimage-fetch: only picked optional rows, sha256 enforced
F=packages/omaxian-firstboot/files/usr/bin/omaxian-appimage-fetch
mkdir -p $T/bin $T/fetch
printf 'good\t-\turl\thttps://x.example/Good.AppImage\toptional\t%s\tGood: g\nbadsum\t-\turl\thttps://x.example/Bad.AppImage\toptional\t%s\tBad: b\nnotpicked\t-\turl\thttps://x.example/No.AppImage\toptional\t-\tNo: n\nunknown\t*u*\tpayload\tUNKNOWN\n' \
	"$(printf 'GOOD' | sha256sum | cut -d' ' -f1)" "$(printf 'GOOD' | sha256sum | cut -d' ' -f1)" > $T/m
printf 'good\nbadsum\n' > $T/picked
cat > $T/bin/curl <<S
#!/bin/sh
echo "\$*" >> $T/curl.log
o=""; u=""; while [ \$# -gt 0 ]; do case "\$1" in -o) o=\$2; shift;; http*) u=\$1;; esac; shift; done
case "\$u" in *Good*) printf GOOD > "\$o";; *) printf EVIL > "\$o";; esac
S
chmod +x $T/bin/curl
PATH=$T/bin:/usr/bin:/bin OMAXIAN_APPIMAGE_MANIFEST=$T/m OMAXIAN_OPTIONAL_APPIMAGES=$T/picked bash $F $T/fetch > $T/fetch.out 2>&1; rc=$?
[ -x $T/fetch/good/Good.AppImage ] && ok "fetch: picked + sha256 OK -> cached" || { bad "fetch good"; cat $T/fetch.out; }
[ ! -e $T/fetch/badsum/Bad.AppImage ] && [ ! -e $T/fetch/badsum/Bad.AppImage.part ] && grep -q "badsum: sha256 mismatch" $T/fetch.out && [ $rc = 1 ] && ok "fetch: sha256 mismatch rejected, rc=1 (retried)" || { bad "fetch badsum"; cat $T/fetch.out; }
! grep -q No.AppImage $T/curl.log && [ ! -d $T/fetch/notpicked ] && ok "fetch: unpicked optional row skipped" || bad "fetch notpicked"
grep -q "?? unknown: no upstream URL" $T/fetch.out && ok "fetch: payload-only row reported" || bad "fetch payload row"
# 6 full build payload filter: copies only bundled rows (no optional, no OpenSpot)
grep -q 'class:-bundled} == optional' scripts/build-rootfs.sh && ! grep -q 'cp -a "$PAYLOADDIR/appimages"' scripts/build-rootfs.sh \
	&& ok "full build copies only bundled manifest rows from payload/appimages" || bad "payload filter"
# 7 user first run: unpicked extra apps skipped
grep -q 'optional-appimages.list' packages/omaxian-firstboot/files/usr/bin/omaxian-user-firstrun && ok "user firstrun honours the pick" || bad "user firstrun"
echo "$pass passed, $fail failed"; [ $fail = 0 ]

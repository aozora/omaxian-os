#!/bin/bash
# Omaxian OS 0.2 "Space Cat": version wiring, XFCE/Thunar removal, community
# apps, installer file-manager page (Strata|Folio) and OnlyOffice
# DesktopEditors.conf titlebar=system. Hermetic (stub libcalamares, no chroot).
set -u
cd "$(dirname "$0")/.."
pass=0; fail=0
ok() { echo "ok   $*"; pass=$((pass+1)); }; bad() { echo "FAIL $*"; fail=$((fail+1)); }
T=$(mktemp -d); trap 'rm -rf $T' EXIT
S=packages/omaxian-session/files
C=packages/omaxian-calamares-settings/files
INI=$S/usr/libexec/omaxian/ini-set
FM=$S/usr/bin/omaxian-default-file-manager

# 1 version / codename
( . config/build.conf
  [ "$OMAXIAN_VERSION" = 0.3 ] && [ "$OMAXIAN_CODENAME" = "Space Cat" ] && [ "$OMAXIAN_CODENAME_ID" = space-cat ] ) \
	&& ok "build.conf: 0.3 \"Space Cat\" (space-cat)" || bad "build.conf version/codename"
( . config/build.conf; for f in base full; do
	v=$(echo "OMAXIAN_${OMAXIAN_VERSION}_${OMAXIAN_CODENAME_TAG}_$f" | tr 'a-z.-' 'A-Z__' | cut -c1-32)
	[ "$v" = "OMAXIAN_0_3_SPACE_CAT_$(echo $f | tr a-z A-Z)" ] || exit 1; done ) \
	&& ok "ISO volume ids OMAXIAN_0_3_SPACE_CAT_{BASE,FULL} (not truncated)" || bad "volid"
( . config/build.conf; [ "$OMAXIAN_SHELL_REF" = v1.2.4 ] ) \
	&& ok "Omaxian shell ref v1.2.4" || bad "shell ref"
pin=$(. config/build.conf; printf %s "$OMAXIAN_SHELL_COMMIT")
[ ${#pin} = 40 ] && ok "Omaxian shell v1.2.4 pinned to $pin" || bad "shell commit (set when tag v1.2.4 is published)"
[ "$(dpkg-parsechangelog -l packages/omaxian-session/debian/changelog -S Version)" = 1.2.4-1 ] \
	&& ok "omaxian-session changelog 1.2.4-1" || bad "session version"
[ "$(dpkg-parsechangelog -l packages/omaxian-strata/debian/changelog -S Version)" = 1.2.2-1 ] \
	&& ok "omaxian-strata changelog 1.2.2-1" || bad "strata version"
grep -q 'Space Cat\|space-cat' tools/diag/installvm.sh tools/diag/liveboot.sh && ! grep -rq 'trans-siberian' tools/diag/installvm.sh tools/diag/liveboot.sh \
	&& ok "diag scripts use the 0.2 ISO names" || bad "diag ISO names"

# 2 no XFCE desktop / Thunar; the shell's XFCE deps stay
L=$(grep -hvE '^\s*(#|$)' config/package-lists/*.list | sed 's/#.*//' | tr -s ' \t' '\n' | sed '/^$/d')
bad_x=$(echo "$L" | grep -E '^(xfce4|xfce4-(session|panel|settings|appfinder|terminal|notifyd|screenshooter|taskmanager|whiskermenu-plugin|pulseaudio-plugin)|xfdesktop4|xfwm4|thunar.*|tumbler|mousepad|ristretto)$' || true)
[ -z "$bad_x" ] && ok "package lists: no XFCE desktop / Thunar" || bad "package lists still have: $bad_x"
echo "$L" | grep -qx xfce4-power-manager && echo "$L" | grep -qx xfconf && echo "$L" | grep -qx 'xfce4-power-manager-plugins-' \
	&& ok "xfce4-power-manager + xfconf kept (shell runs them), panel plugin excluded" || bad "xfpm/xfconf"
! grep -qw thunar packages/omaxian-session/debian/control && grep -q 'xfce4-power-manager, xfconf' packages/omaxian-session/debian/control \
	&& ok "omaxian-session: no thunar; xfpm + xfconf in Depends" || bad "session control"
grep -q '^METAS="network-manager-gnome"$' $C/usr/libexec/omaxian/keep-manual && ok "keep-manual METAS without xfce4" || bad "keep-manual METAS"
grep -q 'XFCE_GONE=' scripts/build-rootfs.sh && grep -q 'XFCE desktop / Thunar packages got installed' scripts/build-rootfs.sh \
	&& ok "build-rootfs fails if XFCE/Thunar get installed" || bad "build guard"

# 3 community apps
grep -q 'find "$APPS" -mindepth 2 -maxdepth 2 -name install.sh' scripts/build-community-apps.sh \
	&& ok "build-community-apps enumerates every community-apps/<id>/install.sh" || bad "apps not enumerated"
grep -q 'omaxian-prebuilt' scripts/build-community-apps.sh && grep -q "did not install its pinned pre-built binary" scripts/build-community-apps.sh \
	&& grep -q 'for t in cmake qmake6 qmake cargo rustup cc' scripts/build-community-apps.sh \
	&& ok "build-community-apps: pinned pre-built binaries only, compilers blocked" || bad "prebuilt path"
! grep -q 'SOURCE_APPS=' scripts/build-community-apps.sh && ! grep -q 'COPY_APPS=' scripts/build-community-apps.sh \
	&& grep -q 'has no pinned pre-built binary' scripts/build-community-apps.sh \
	&& ok "flowtunes, fantasi and local-ai use pinned prebuilts like the other apps" || bad "unpinned apps"
! grep -qx vlc config/package-lists/*.list && grep -qx chezmoi config/package-lists/40-user.list \
	&& grep -qx rustic config/package-lists/40-user.list && grep -qx xsecurelock config/package-lists/40-user.list \
	&& grep -qx shellcheck config/package-lists/40-user.list && grep -qx slop config/package-lists/40-user.list \
	&& grep -qx heif-thumbnailer config/package-lists/40-user.list \
	&& grep -qx qt6-image-formats-plugins config/package-lists/55-community-apps.list \
	&& grep -q '^Package: vlc' config/apt/preferences.d/20-omaxian-blocklist.pref \
	&& ok "0.3 packages added; vlc/imv/nsxiv blocked" || bad "package list delta"
[ ! -e patches/community-apps ] && ok "no local community-app patches (Qt 6.8 fixes upstream in v1.2.1)" || bad "patches/community-apps still present"
for d in qml6-module-qtquick-pdf qml6-module-qtquick-dialogs qml6-module-qtcore libarchive-tools udisks2 ffmpegthumbnailer libglib2.0-0t64 libturbojpeg0; do
	grep -qx "$d" config/package-lists/55-community-apps.list && grep -q "$d" packages/omaxian-session/debian/control || bad "dep $d"
done; ok "new app runtime deps in 55-community-apps.list and session Depends"

# 4 ini-set
f=$T/a.conf
printf '# c\n[General]\nfoo=1\n\n[Other]\nx=y\n' > $f
sh $INI $f General titlebar system && sh $INI --if-missing $f General titlebar custom && sh $INI $f Other x z
[ "$(cat $f)" = "$(printf '# c\n[General]\nfoo=1\ntitlebar=system\n\n[Other]\nx=z')" ] && ok "ini-set: adds/keeps/replaces, other lines untouched" || { bad "ini-set"; cat $f; }
rm -f $T/n/new.conf; sh $INI $T/n/new.conf General titlebar system
[ "$(cat $T/n/new.conf)" = "$(printf '[General]\ntitlebar=system')" ] && ok "ini-set: creates file + section" || bad "ini-set create"

# 5 omaxian-default-file-manager (as a user)
H=$T/home; mkdir -p $H/.config
printf '[Default Applications]\ntext/plain=plain.desktop\n' > $H/.config/mimeapps.list
HOME=$H OMAXIAN_INI_SET=$INI sh $FM folio >/dev/null
grep -qx 'inode/directory=folio.desktop' $H/.config/mimeapps.list && grep -qx 'text/plain=plain.desktop' $H/.config/mimeapps.list \
	&& ok "file manager: folio -> inode/directory=folio.desktop, other defaults kept" || bad "fm folio"
HOME=$H OMAXIAN_INI_SET=$INI sh $FM strata >/dev/null
[ "$(grep -c '^inode/directory=' $H/.config/mimeapps.list)" = 1 ] && grep -qx 'inode/directory=io.github.lgse.Strata.desktop' $H/.config/mimeapps.list \
	&& ok "file manager: strata replaces it (one entry)" || bad "fm strata"
! HOME=$H OMAXIAN_INI_SET=$INI sh $FM nautilus 2>/dev/null && ok "file manager: unknown name rejected" || bad "fm unknown"
# --system + --login (only when unset)
OMAXIAN_FM_SYS=$T/etc/file-manager sh $FM --system folio && [ "$(cat $T/etc/file-manager)" = folio ] && ok "--system records the choice" || bad "--system"
H2=$T/home2; mkdir -p $H2/.config; printf '[Default Applications]\nx=y.desktop\n' > $H2/.config/mimeapps.list
HOME=$H2 OMAXIAN_FM_SYS=$T/etc/file-manager OMAXIAN_INI_SET=$INI sh $FM --login
grep -qx 'inode/directory=folio.desktop' $H2/.config/mimeapps.list && ok "--login applies the system choice when unset" || bad "--login apply"
HOME=$H OMAXIAN_FM_SYS=$T/etc/file-manager OMAXIAN_INI_SET=$INI sh $FM --login
grep -qx 'inode/directory=io.github.lgse.Strata.desktop' $H/.config/mimeapps.list && ok "--login never overrides a user's choice" || bad "--login override"

# 6 OnlyOffice
[ "$(cat $S/etc/skel/.config/onlyoffice/DesktopEditors.conf)" = "$(printf '[General]\ntitlebar=system')" ] && ok "/etc/skel DesktopEditors.conf: [General] titlebar=system" || bad "skel conf"
H3=$T/home3; mkdir -p $H3/.config/onlyoffice; printf '[General]\nUITheme=theme-dark\ntitlebar=custom\n' > $H3/.config/onlyoffice/DesktopEditors.conf
HOME=$H3 OMAXIAN_INI_SET=$INI sh $S/usr/libexec/omaxian/onlyoffice-defaults
grep -qx 'titlebar=custom' $H3/.config/onlyoffice/DesktopEditors.conf && ok "onlyoffice-defaults (login): keeps a user's titlebar" || bad "oo login"
H4=$T/home4; mkdir -p $H4
HOME=$H4 OMAXIAN_INI_SET=$INI sh $S/usr/libexec/omaxian/onlyoffice-defaults
grep -qx 'titlebar=system' $H4/.config/onlyoffice/DesktopEditors.conf && ok "onlyoffice-defaults (login): creates it when missing" || bad "oo create"
grep -q 'titlebar system' scripts/gen-home-template.sh && ok "home template gets DesktopEditors.conf" || bad "template conf"

# 7 omaxian-seed-home merges INI files the installer already wrote
TP=$T/tpl; mkdir -p $TP/.config/onlyoffice $TP/.local
printf '[Default Applications]\napplication/x-omarchy-meeting=omarchy-meeting-recorder.desktop\n' > $TP/.config/mimeapps.list
printf '[General]\ntitlebar=system\n' > $TP/.config/onlyoffice/DesktopEditors.conf
echo hi > $TP/.local/file
H5=$T/home5; mkdir -p $H5/.config; printf '[Default Applications]\ninode/directory=folio.desktop\n' > $H5/.config/mimeapps.list
HOME=$H5 OMAXIAN_HOME_TEMPLATE=$TP OMAXIAN_INI_SET=$INI sh $S/usr/bin/omaxian-seed-home
grep -qx 'inode/directory=folio.desktop' $H5/.config/mimeapps.list && grep -qx 'application/x-omarchy-meeting=omarchy-meeting-recorder.desktop' $H5/.config/mimeapps.list \
	&& [ -f $H5/.local/file ] && [ -f $H5/.config/onlyoffice/DesktopEditors.conf ] \
	&& ok "seed-home: template copied, installer's mimeapps entry kept and merged" || bad "seed-home merge"

# 8 Calamares: page + job
python3 - "$C/etc/calamares" <<'PY' && ok "Calamares: packagechooser@filemanager page (required, legacy, default strata, items strata+folio, images exist)" || bad "packagechooser config"
import sys, os, yaml
d = sys.argv[1]
s = yaml.safe_load(open(d + "/settings.conf"))
inst = {i["id"]: i for i in s["instances"]}
assert inst["filemanager"]["module"] == "packagechooser"
show = [m for st in s["sequence"] if "show" in st for m in st["show"]]
assert show.index("packagechooser@filemanager") > show.index("users") and show.index("packagechooser@filemanager") < show.index("summary")
exe = [m for st in s["sequence"] if "exec" in st for m in st["exec"]]
assert exe.index("omaxianuserdefaults") > exe.index("packages") > exe.index("users")
c = yaml.safe_load(open(d + "/modules/" + inst["filemanager"]["config"]))
assert c["mode"] == "required" and c["method"] == "legacy" and c["default"] == "strata"
assert [i["id"] for i in c["items"]] == ["strata", "folio"]
root = os.path.abspath(d + "/../..")
for i in c["items"]:
    assert os.path.isfile(root + i["screenshot"]), i["screenshot"]
PY
mkdir -p $T/py/libcalamares
cat > $T/py/libcalamares/__init__.py <<'PY'
import json, os
class _GS:
    def __init__(self): self.d = json.load(open(os.environ["GS"]))
    def value(self, k): return self.d.get(k)
    def contains(self, k): return k in self.d
    def keys(self): return list(self.d)
globalstorage = _GS()
calls = []
class utils:
    @staticmethod
    def warning(m): print("W:", m)
    @staticmethod
    def debug(m): print("D:", m)
    @staticmethod
    def target_env_call(cmd):
        calls.append(cmd); return 0
PY
for case in "folio:folio" "strata:strata" "none:strata"; do
	pick=${case%%:*}; want=${case#*:}
	if [ $pick = none ]; then echo '{"username":"marcello"}' > $T/gs.json
	else echo "{\"username\":\"marcello\",\"packagechooser_filemanager\":\"$pick\"}" > $T/gs.json; fi
	GS=$T/gs.json WANT=$want PYTHONPATH=$T/py python3 - <<'PY' >$T/py.out 2>&1 && ok "omaxianuserdefaults: pick=$pick -> $want for marcello + OnlyOffice" || { bad "job pick=$pick"; cat $T/py.out; }
import importlib.util, os, sys
import libcalamares
D = "packages/omaxian-calamares-settings/files/usr/lib/x86_64-linux-gnu/calamares/modules/"
sp = importlib.util.spec_from_file_location("u", D + "omaxianuserdefaults/main.py")
m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
assert m.run() is None
w = os.environ["WANT"]
assert libcalamares.calls == [["/usr/bin/omaxian-default-file-manager", "--system", w],
    ["/usr/bin/omaxian-default-file-manager", "--user", "marcello", w],
    ["/usr/libexec/omaxian/onlyoffice-defaults", "marcello"]], libcalamares.calls
PY
done

# 9 root path of the helpers (real chown) when we are root via sudo
if sudo -n true 2>/dev/null; then
	sudo useradd -M -d $T/uhome omxtest 2>/dev/null; sudo mkdir -p $T/uhome; sudo chown omxtest: $T/uhome
	sudo env OMAXIAN_INI_SET=$INI sh $S/usr/libexec/omaxian/onlyoffice-defaults omxtest
	sudo env OMAXIAN_INI_SET=$INI OMAXIAN_FM_SYS=$T/etc/file-manager sh $FM --user omxtest folio
	o1=$(stat -c %U $T/uhome/.config/onlyoffice/DesktopEditors.conf); o2=$(stat -c %U $T/uhome/.config/onlyoffice); o3=$(stat -c %U $T/uhome/.config/mimeapps.list)
	[ "$o1$o2$o3" = omxtestomxtestomxtest ] && grep -qx titlebar=system $T/uhome/.config/onlyoffice/DesktopEditors.conf \
		&& grep -qx inode/directory=folio.desktop $T/uhome/.config/mimeapps.list \
		&& ok "root helpers: files + new dirs owned by the user" || bad "ownership ($o1 $o2 $o3)"
	sudo rm -rf $T/uhome; sudo userdel omxtest 2>/dev/null
fi

echo "== $pass passed, $fail failed"
[ $fail = 0 ]

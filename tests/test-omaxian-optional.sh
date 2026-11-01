#!/bin/bash
# Round 14: omaxian-optional (add optional groups/AppImages after install),
# OnlyOffice in both ISOs (manifest class "base": not re-downloaded, plain menu
# entry until Gear Lever integrates it) and the XDG user folders fix in
# omaxian-user-setup. Hermetic: OMAXIAN_FB_ROOT prefix + stub apt-get, flatpak,
# dpkg-query, curl, sudo; no network, no root.
set -u
cd "$(dirname "$0")/.."
P=packages/omaxian-firstboot/files
pass=0; fail=0
ok() { echo "ok   $*"; pass=$((pass+1)); }; bad() { echo "FAIL $*"; fail=$((fail+1)); }

setup() {
	T=$(mktemp -d); export HOME=$T/home; mkdir -p $HOME
	S=$T/usr/share/omaxian; mkdir -p $S/payload/appimages $S/payload/debs $T/var/lib/omaxian $T/var/log $T/bin $T/usr/bin $T/usr/sbin
	cp $P/usr/bin/omaxian-optional $P/usr/bin/omaxian-appimage-fetch $P/usr/bin/omaxian-user-firstrun $T/usr/bin/
	cp $P/usr/sbin/omaxian-optional-appimage $T/usr/sbin/
	cp config/optional-groups.list config/optional-groups-full.list $S/
	printf 'office\t*office*\tgithub\tx/office|re\tbase\nalpha\t*alpha*\tgithub\tx/alpha|re\nextra\t-\turl\thttps://x.example/Extra.AppImage\toptional\t-\tExtra: an extra app\n' > $S/appimages.manifest
	# fake AppImage: --appimage-extract writes squashfs-root/{office.desktop,.DirIcon -> office.png}
	cat > $S/payload/appimages/Office-1.AppImage <<'A'
#!/bin/sh
[ "$1" = --appimage-extract ] || exit 1
mkdir -p squashfs-root
case "$2" in
*.desktop) printf '[Desktop Entry]\nName=Office Editors\nComment=Edit documents\nExec=desktopeditors %%F\nIcon=office\nMimeType=application/x-doc;\nCategories=Office;\n' > squashfs-root/office.desktop;;
.DirIcon) ln -sf office.png squashfs-root/.DirIcon;;
office.png) echo PNG > squashfs-root/office.png;;
esac
A
	chmod +x $S/payload/appimages/Office-1.AppImage
	echo deb > $S/payload/debs/omaxian-voxtype_1.1.1-3_all.deb
	: > $T/installed
	cat > $T/bin/dpkg-query <<D
#!/bin/sh
for a; do p=\$a; done; grep -qx "\$p" $T/installed && echo installed || echo not-installed
D
	cat > $T/bin/apt-get <<D
#!/bin/sh
echo "apt-get \$*" >> $T/apt.log
[ "\$1" = update ] && exit 0
for a; do p=\$a; done; case "\$p" in */*.deb) echo voxtype >> $T/installed; echo omaxian-voxtype >> $T/installed;; *) echo "\$p" >> $T/installed;; esac
D
	cat > $T/bin/flatpak <<D
#!/bin/sh
echo "flatpak \$*" >> $T/flatpak.log
case "\$1" in info) for a; do p=\$a; done; grep -qx "\$p" $T/installed;; install) for a; do p=\$a; done; echo "\$p" >> $T/installed;; *) exit 0;; esac
D
	cat > $T/bin/curl <<D
#!/bin/sh
echo "curl \$*" >> $T/curl.log
o=""; while [ \$# -gt 0 ]; do [ "\$1" = -o ] && { o=\$2; shift; }; shift; done
[ -n "\$o" ] && echo VOXDEB > "\$o"; exit 0
D
	chmod +x $T/bin/*
	printf 'VOXTYPE_URL=https://github.com/x/voxtype/releases/download/v1.1.1/voxtype_1.1.1-1_amd64.deb\nVOXTYPE_SHA256=%s\n' \
		"$(echo VOXDEB | sha256sum | cut -d' ' -f1)" > $S/voxtype.pin
}
OPT() { PATH=$T/bin:/usr/bin:/bin OMAXIAN_FB_ROOT=$T OMAXIAN_OPTIONAL_LOG=$T/var/log/opt.log OMAXIAN_FIRSTRUN_NO_GEARLEVER=1 timeout 60 bash $T/usr/bin/omaxian-optional "$@" </dev/null; }

# 1 list: the 6 base groups + VoxType + AppImages, with status
setup; out=$(OPT list)
for g in browser-chromium mail-thunderbird graphics chat-telegram chat-discord share-packet gearlever containers virtualization voice-voxtype office alpha extra; do
	grep -q "^  $g " <<<"$out" || bad "list misses $g"; done
grep -q "^  containers .*\[not installed\]" <<<"$out" && grep -q "^  office .*in both ISOs" <<<"$out" && grep -q "^  extra .*extra app" <<<"$out" \
	&& ok "list: 7 groups (incl. VoxType) and the AppImages with status" || { bad "list"; echo "$out"; }
# 2 install containers: apt one package per run, Podman Desktop from Flathub, firstboot records updated
OPT install containers >/dev/null 2>&1
n=$(grep -c ' install ' $T/apt.log)
[ "$n" = 6 ] && grep -qx docker-compose $T/installed && grep -q "install --system -y --noninteractive flathub io.podman_desktop.PodmanDesktop" $T/flatpak.log \
	&& grep -qx podman $T/var/lib/omaxian/optional-packages.list && grep -q "remote-add --system --if-not-exists flathub" $T/flatpak.log \
	&& ok "install containers: 6 apt runs + Podman Desktop; podman recorded for firstboot" || { bad "containers"; cat $T/apt.log $T/flatpak.log; }
OPT list | grep -q "^  containers .*\[installed\]" && ok "status after install: installed" || bad "status installed"
# 3 Telegram (Flatpak-only group) is recorded as picked (firstboot would otherwise prune it on the full ISO)
rm -f $T/var/lib/omaxian/optional-flatpaks.list
OPT install chat-discord >/dev/null 2>&1
[ ! -e $T/var/lib/omaxian/optional-flatpaks.list ] && grep -q "flathub com.discordapp.Discord" $T/flatpak.log \
	&& ok "install chat-discord without an installer record: Flathub, no record created (would unpick the others)" || bad "discord no record"
: > $T/var/lib/omaxian/optional-flatpaks.list
OPT install chat-telegram >/dev/null 2>&1
grep -qx org.telegram.desktop $T/var/lib/omaxian/optional-flatpaks.list && grep -q "flathub org.telegram.desktop" $T/flatpak.log \
	&& ok "install chat-telegram: Flathub + recorded in optional-flatpaks.list" || bad "telegram"
# 4 VoxType: pinned .deb (sha256 ok) + omaxian-voxtype from the payload in one apt run
OPT install voice-voxtype >/dev/null 2>&1
grep -q "install .*/voxtype_1.1.1-1_amd64.deb $T/usr/share/omaxian/payload/debs/omaxian-voxtype_1.1.1-3_all.deb" $T/apt.log && grep -qx voxtype $T/installed \
	&& ok "install voice-voxtype: pinned upstream .deb + omaxian-voxtype" || { bad "voxtype"; cat $T/apt.log; }
rm -rf $T
# 5 VoxType sha256 mismatch: nothing installed, error exit
setup; sed -i 's/^VOXTYPE_SHA256=.*/VOXTYPE_SHA256='"$(printf 0%.0s {1..64})"'/' $S/voxtype.pin
OPT install voice-voxtype >/dev/null 2>&1; rc=$?
[ $rc != 0 ] && ! grep -q ' install ' $T/apt.log 2>/dev/null && grep -q "sha256 mismatch" $T/var/log/opt.log && ok "VoxType sha256 mismatch: refused" || bad "voxtype mismatch (rc=$rc)"
# 6 unknown id
OPT install nosuch >/dev/null 2>&1 && bad "unknown id accepted" || ok "unknown id rejected"
# 7 AppImage of class base: from the payload, no download, plain menu entry without Gear Lever
: > $T/curl.log; OPT install office >/dev/null 2>&1
d=$HOME/.local/share/applications/omaxian-appimage-office.desktop
[ -x $HOME/AppImages/Office-1.AppImage ] && [ ! -s $T/curl.log ] && grep -q '^Exec="'$HOME'/AppImages/Office-1.AppImage" %F$' $d \
	&& grep -q '^Name=Office Editors$' $d && grep -q '^MimeType=application/x-doc;$' $d && grep -q "^Icon=$HOME/.local/share/icons/omaxian-appimage-office.png$" $d \
	&& [ -s $HOME/.local/share/icons/omaxian-appimage-office.png ] && ok "install office: payload copy into ~/AppImages, menu entry from its .desktop + icon, no download" \
	|| { bad "office"; cat $d; ls -la $HOME/AppImages; cat $T/curl.log 2>/dev/null; }
# 8 extra app: recorded as picked and fetched (only that id)
OPT install extra >/dev/null 2>&1
grep -qx extra $T/var/lib/omaxian/optional-appimages.list && grep -q "https://x.example/Extra.AppImage" $T/curl.log && ! grep -q "x/alpha" $T/curl.log \
	&& ok "install extra: picked + only that AppImage downloaded" || { bad "extra"; cat $T/curl.log; }
rm -rf $T

# 9 omaxian-appimage-fetch: class base not downloaded while bundled; downloaded when not
setup; mkdir -p $T/c
PATH=$T/bin:/usr/bin:/bin OMAXIAN_APPIMAGE_MANIFEST=$S/appimages.manifest OMAXIAN_PAYLOAD=$S/payload OMAXIAN_OPTIONAL_APPIMAGES=$T/none \
	bash $P/usr/bin/omaxian-appimage-fetch $T/c > $T/f.out 2>&1
grep -q "office: bundled in the ISO, not downloaded" $T/f.out && ! grep -q "x/office" $T/curl.log && grep -q "x/alpha" $T/curl.log \
	&& ok "fetch: OnlyOffice (class base, bundled) skipped, bundled rows still fetched" || { bad "fetch base"; cat $T/f.out; }
rm -rf $T

# 10 user-firstrun: menu entry until Gear Lever, then Gear Lever integration removes it
setup
PATH=$T/bin:/usr/bin:/bin OMAXIAN_FB_ROOT=$T OMAXIAN_FIRSTRUN_NO_GEARLEVER=1 bash $P/usr/bin/omaxian-user-firstrun
[ -s $HOME/.local/share/applications/omaxian-appimage-office.desktop ] && [ ! -e $HOME/.local/state/omaxian/user-firstrun.done ] \
	&& grep -q "office: menu entry" $HOME/.local/state/omaxian/user-firstrun.log && ok "firstrun without Gear Lever: OnlyOffice menu entry, still pending" || bad "firstrun fallback"
cat >> $T/bin/flatpak <<'D'
D
cat > $T/bin/flatpak <<D
#!/bin/sh
echo "flatpak \$*" >> $T/flatpak.log; exit 0
D
mkdir -p $T/var/lib/omaxian/appimages/alpha && touch $T/var/lib/omaxian/appimages/alpha/Alpha.AppImage
PATH=$T/bin:/usr/bin:/bin OMAXIAN_FB_ROOT=$T bash $P/usr/bin/omaxian-user-firstrun
[ ! -e $HOME/.local/share/applications/omaxian-appimage-office.desktop ] && grep -q "integrate $HOME/AppImages/Office-1.AppImage" $T/flatpak.log \
	&& [ -e $HOME/.local/state/omaxian/user-firstrun.done ] && ok "firstrun with Gear Lever: integrated, plain entry removed, done" || { bad "firstrun gearlever"; cat $HOME/.local/state/omaxian/user-firstrun.log; }
rm -rf $T

# 11 build wiring: OnlyOffice is class base; s_payload copies class base + omaxian-voxtype; firstboot ships the lists
grep -P '^onlyoffice\t.*\tbase$' config/appimages.manifest >/dev/null && grep -q 'stage payload s_payload' scripts/build-rootfs.sh \
	&& grep -q 'optional-groups-full.list" "$1/files/usr/share/omaxian/"' scripts/build-packages.sh && grep -q 'voxtype.pin' scripts/build-packages.sh \
	&& grep -q '^Terminal=true' $P/usr/share/applications/omaxian-optional.desktop && grep -q '^Exec=omaxian-optional$' $P/usr/share/applications/omaxian-optional.desktop \
	&& ok "build wiring: class base, s_payload, group lists + voxtype pin in omaxian-firstboot, menu entry" || bad "build wiring"
b=$(grep -vE '^\s*(#|$)' scripts/gen-netinstall.sh >/dev/null; bash scripts/gen-netinstall.sh config/optional-groups.list /dev/stdout --appimages config/appimages.manifest | grep -c 'omaxian-pick:appimage:onlyoffice')
[ "$b" = 0 ] && ok "OnlyOffice is not offered as an installer checkbox" || bad "onlyoffice in netinstall"

# 12 XDG user folders: created on every login, also when the home is already seeded
T=$(mktemp -d); export HOME=$T/home; mkdir -p $HOME/.local/share/omarchy/bin $T/bin
touch $HOME/.xsessionrc; printf '#!/bin/sh\n' > $HOME/.local/share/omarchy/bin/omarchy-launch-shell; chmod +x $HOME/.local/share/omarchy/bin/omarchy-launch-shell
printf '#!/bin/sh\necho run >> %s/xdg.log\nfor d in Desktop Documents Downloads Music Pictures Videos Templates Public; do mkdir -p "$HOME/$d"; done\n' $T > $T/bin/xdg-user-dirs-update; chmod +x $T/bin/xdg-user-dirs-update
sed 's|^TEMPLATE=.*|TEMPLATE='$T'/tpl|' packages/omaxian-session/files/usr/bin/omaxian-user-setup > $T/us; mkdir -p $T/tpl
PATH=$T/bin:/usr/bin:/bin sh $T/us
[ -s $T/xdg.log ] && [ -d $HOME/Documents ] && [ -d $HOME/Downloads ] && [ -d $HOME/Videos ] && ok "user-setup: xdg-user-dirs-update runs on an already seeded home" || bad "xdg dirs"
rm -rf $T

echo "omaxian-optional/onlyoffice/xdg: $pass passed, $fail failed"; [ $fail = 0 ]

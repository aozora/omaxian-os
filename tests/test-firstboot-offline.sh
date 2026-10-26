#!/bin/bash
# omaxian-firstboot offline completion (full ISO marker /var/lib/omaxian/full-offline).
# Hermetic: OMAXIAN_FB_ROOT prefix + stub curl/flatpak/dpkg-query; no network.
set -u
cd "$(dirname "$0")/.."
FB=packages/omaxian-firstboot/files/usr/sbin/omaxian-firstboot
pass=0; fail=0
ok() { echo "ok   $*"; pass=$((pass+1)); }; bad() { echo "FAIL $*"; fail=$((fail+1)); }

setup() { # setup <online 0|1>
	T=$(mktemp -d)
	mkdir -p $T/var/log $T/var/lib/omaxian $T/usr/share/omaxian/payload/appimages $T/bin $T/etc/apt
	printf 'deb http://deb.example/merged excalibur main\n' > $T/etc/apt/sources.list
	printf '# comment\napp.One\nio.podman_desktop.PodmanDesktop\nus.zoom.Zoom\n' > $T/usr/share/omaxian/flatpaks.list
	printf 'alpha\t*alpha*\tgithub\tx/alpha|re\nbeta\t*beta*\tpayload\t-\nextra\t-\turl\thttps://x.example/Extra.AppImage\toptional\t-\tExtra: an extra app\n' > $T/usr/share/omaxian/appimages.manifest
	touch $T/usr/share/omaxian/payload/appimages/Alpha-1.AppImage $T/usr/share/omaxian/payload/appimages/beta.appimage
	printf 'app.One\nio.podman_desktop.PodmanDesktop\nus.zoom.Zoom\norg.telegram.desktop\n' > $T/flatpaks-installed
	printf '# generated\nchat-telegram|org.telegram.desktop\n' > $T/usr/share/omaxian/optional-flatpaks.list
	: > $T/var/lib/omaxian/optional-pending.list
	printf 'krita\npodman\n' > $T/var/lib/omaxian/optional-packages.list
	date -Is > $T/var/lib/omaxian/full-offline
	cat > $T/bin/curl <<S
#!/bin/sh
[ "$1" = 1 ] && { echo 200; exit 0; }
case "\$*" in *http_code*) echo 000;; esac; exit 7
S
	cat > $T/bin/flatpak <<S
#!/bin/sh
echo "\$*" >> $T/flatpak.log
[ "\$1" = info ] && { grep -qx "\$3" $T/flatpaks-installed; exit; }
if [ "\$1" = uninstall ]; then for a; do p=\$a; done; sed -i "/^\$p\\\$/d" $T/flatpaks-installed; fi
if [ "\$1" = install ]; then for a; do p=\$a; done; echo "\$p" >> $T/flatpaks-installed; fi
exit 0
S
	printf '#!/bin/sh\necho installed\n' > $T/bin/dpkg-query
	chmod +x $T/bin/*
}
run() { PATH=$T/bin:/usr/bin:/bin OMAXIAN_FB_ROOT=$T timeout 30 bash $FB "$@"; echo $?; }
done_() { [ -f $T/var/lib/omaxian/firstboot.done ]; }
log() { cat $T/var/log/omaxian-firstboot.log; }

# 1 full ISO, nothing missing, offline, --boot: done at once (no 10 min network wait)
setup 0; s=$(date +%s); rc=$(run --boot); e=$(( $(date +%s) - s ))
done_ && [ "$rc" = 0 ] && [ $e -lt 20 ] && log | grep -q "everything installed offline" && ok "full complete offline (--boot): done in ${e}s" || { bad "full complete offline"; log; }; rm -rf $T
# 2 same with --now
setup 0; run --now >/dev/null; done_ && ok "full complete offline (--now): done" || bad "full --now"; rm -rf $T
# 3 pending optional package: not done
setup 0; echo krita > $T/var/lib/omaxian/optional-pending.list; run >/dev/null
! done_ && log | grep -q "optional packages pending: krita" && ok "pending krita: not done" || { bad "pending"; log; }; rm -rf $T
# 4 a Flatpak missing: not done
setup 0; sed -i '/Zoom/d' $T/flatpaks-installed; run >/dev/null
! done_ && log | grep -q "flatpak us.zoom.Zoom missing" && ok "Zoom missing: not done" || { bad "flatpak missing"; log; }; rm -rf $T
# 5 an AppImage missing from payload and cache: not done
setup 0; rm $T/usr/share/omaxian/payload/appimages/beta.appimage; run >/dev/null
! done_ && log | grep -q "AppImage beta missing" && ok "AppImage missing: not done" || { bad "appimage missing"; log; }; rm -rf $T
# 6 AppImage only in the fresh cache counts
setup 0; rm $T/usr/share/omaxian/payload/appimages/beta.appimage; mkdir -p $T/var/lib/omaxian/appimages/beta; touch $T/var/lib/omaxian/appimages/beta/b.AppImage; run >/dev/null
done_ && ok "AppImage from cache: done" || { bad "cache appimage"; log; }; rm -rf $T
# 7 Podman Desktop not required when Containers was not picked
setup 0; sed -i '/podman/d' $T/flatpaks-installed $T/var/lib/omaxian/optional-packages.list; run >/dev/null
done_ && ok "Podman Desktop skipped (containers not picked): done" || { bad "podman skip"; log; }; rm -rf $T
# 8 Podman Desktop required when Containers was picked
setup 0; sed -i '/podman/d' $T/flatpaks-installed; run >/dev/null
! done_ && ok "Podman Desktop missing (containers picked): not done" || bad "podman required"; rm -rf $T
# 9 base ISO (no marker): keeps retrying offline
setup 0; rm $T/var/lib/omaxian/full-offline; run >/dev/null
! done_ && log | grep -q "offline: will retry" && ok "base ISO offline: not done, retries" || { bad "base"; log; }; rm -rf $T
# 10 full ISO but online: normal online path (updates), no offline shortcut
setup 1; run >/dev/null
! log | grep -q "everything installed offline" && ok "full online: normal online path" || { bad "online"; log; }; rm -rf $T
# 11 all 7 groups incl. VoxType (full-only, installed from the pool): done offline
setup 0; printf 'krita\npodman\nvoxtype\nomaxian-voxtype\n' > $T/var/lib/omaxian/optional-packages.list; run --boot >/dev/null
done_ && log | grep -q "everything installed offline" && ok "VoxType group installed offline: done" || { bad "voxtype done"; log; }; rm -rf $T
# 12 base ISO, online, pending optional package, but apt-get update fails (e.g.
#    apt.omaxian.org or another source unreachable): firstboot goes on with the
#    lists it has, installs the package and clears it from the pending list
setup 1; rm $T/var/lib/omaxian/full-offline; echo krita > $T/var/lib/omaxian/optional-pending.list
cat > $T/bin/dpkg-query <<S
#!/bin/sh
for a; do p=\$a; done; grep -qx "\$p" $T/dpkg-installed 2>/dev/null && echo installed || echo not-installed
S
cat > $T/bin/apt-get <<S
#!/bin/sh
case " \$* " in *" update "*) echo "E: Failed to fetch https://apt.omaxian.org/dists/excalibur/InRelease"; exit 100;; esac
for a; do p=\$a; done; echo "\$p" >> $T/dpkg-installed; exit 0
S
chmod +x $T/bin/*; rc=$(run --now)
[ "$rc" = 0 ] && log | grep -q "apt-get update reported errors (continuing" && log | grep -q "apt: optional packages installed" && [ ! -s $T/var/lib/omaxian/optional-pending.list ] \
	&& ok "apt-get update failing: firstboot continues, krita installed" || { bad "apt update failure"; log; }; rm -rf $T
# Telegram = optional Flatpak group (config/optional-groups.list field 6)
FPS=var/lib/omaxian/optional-flatpaks.list
# 13 full ISO, Telegram picked (preinstalled): kept, done offline
setup 0; echo org.telegram.desktop > $T/$FPS; run --boot >/dev/null
done_ && grep -qx org.telegram.desktop $T/flatpaks-installed && ! grep -q "^uninstall" $T/flatpak.log && ok "full ISO, Telegram picked: kept, done offline" || { bad "telegram picked"; log; }; rm -rf $T
# 14 full ISO, Telegram not picked (empty record): removed offline (+ unused runtimes), done
setup 0; : > $T/$FPS; run --boot >/dev/null
done_ && ! grep -qx org.telegram.desktop $T/flatpaks-installed && grep -q "^uninstall --system -y --noninteractive org.telegram.desktop" $T/flatpak.log && grep -q "^uninstall .*--unused" $T/flatpak.log \
	&& log | grep -q "flatpak org.telegram.desktop: removed (group not selected)" && ok "full ISO, Telegram not picked: removed offline, done" || { bad "telegram not picked"; log; cat $T/flatpak.log; }; rm -rf $T
# 15 full ISO, Telegram picked but not in the image: not done offline (retried online)
setup 0; echo org.telegram.desktop > $T/$FPS; sed -i '/telegram/d' $T/flatpaks-installed; run >/dev/null
! done_ && log | grep -q "flatpak org.telegram.desktop missing" && ok "full ISO, Telegram picked but missing: not done" || { bad "telegram missing"; log; }; rm -rf $T
# 16 base ISO online, Telegram picked: installed from Flathub
setup 1; rm $T/var/lib/omaxian/full-offline; echo org.telegram.desktop > $T/$FPS; sed -i '/telegram/d' $T/flatpaks-installed; run --now >/dev/null
grep -q "^install --system -y --noninteractive flathub org.telegram.desktop" $T/flatpak.log && ok "base ISO online, Telegram picked: installed from Flathub" || { bad "telegram base install"; cat $T/flatpak.log; log; }; rm -rf $T
# 17 base ISO online, Telegram not picked: not installed, nothing removed
setup 1; rm $T/var/lib/omaxian/full-offline; : > $T/$FPS; sed -i '/telegram/d' $T/flatpaks-installed; run --now >/dev/null
! grep -qE "^(install|uninstall) .*org.telegram.desktop" $T/flatpak.log && ok "base ISO online, Telegram not picked: not installed" || { bad "telegram base skip"; cat $T/flatpak.log; }; rm -rf $T
# 18 no record (not installed by Calamares): group default (picked) -> kept
setup 0; run >/dev/null
done_ && grep -qx org.telegram.desktop $T/flatpaks-installed && ok "no pick record: Telegram kept (group default)" || { bad "no record"; log; }; rm -rf $T
# Extra apps = optional AppImages (manifest class "optional"): never bundled
AIS=var/lib/omaxian/optional-appimages.list
# 19 full ISO, extra AppImage not picked (empty record): done offline
setup 0; : > $T/$AIS; run --boot >/dev/null
done_ && ok "full ISO, extra AppImage not picked: done offline" || { bad "extra not picked"; log; }; rm -rf $T
# 20 full ISO, extra AppImage picked, not downloaded yet: pending, not done, retried
setup 0; echo extra > $T/$AIS; run --now >/dev/null
! done_ && log | grep -q "extra AppImage extra picked, download pending" && log | grep -q "offline: will retry" && ok "full ISO, extra AppImage picked: pending offline, not done" || { bad "extra picked offline"; log; }; rm -rf $T
# 21 full ISO, extra AppImage picked and already in the cache: done
setup 0; echo extra > $T/$AIS; mkdir -p $T/var/lib/omaxian/appimages/extra; touch $T/var/lib/omaxian/appimages/extra/Extra.AppImage; run >/dev/null
done_ && ok "full ISO, extra AppImage picked and downloaded: done" || { bad "extra cached"; log; }; rm -rf $T
# 22 a bundled-glob file in the payload does not satisfy a picked extra app
setup 0; echo extra > $T/$AIS; touch $T/usr/share/omaxian/payload/appimages/extra.AppImage; run >/dev/null
! done_ && ok "payload copy is ignored for extra apps (cache only)" || { bad "extra payload"; log; }; rm -rf $T
echo "$pass passed, $fail failed"; [ $fail = 0 ]

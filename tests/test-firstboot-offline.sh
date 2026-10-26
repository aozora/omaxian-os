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
	printf 'alpha\t*alpha*\tgithub\tx/alpha|re\nbeta\t*beta*\tpayload\t-\n' > $T/usr/share/omaxian/appimages.manifest
	touch $T/usr/share/omaxian/payload/appimages/Alpha-1.AppImage $T/usr/share/omaxian/payload/appimages/beta.appimage
	printf 'app.One\nio.podman_desktop.PodmanDesktop\nus.zoom.Zoom\n' > $T/flatpaks-installed
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
[ "\$1" = info ] && { grep -qx "\$3" $T/flatpaks-installed; exit; }
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
echo "$pass passed, $fail failed"; [ $fail = 0 ]

#!/bin/bash
exec > >(tee /tmp/r18-installed.log /dev/ttyS0) 2>&1
set +e; D=$(dirname "$0"); . $D/common.sh; U=tester; H=/home/tester
echo R18_INSTALLED_START; date -Iseconds
c_versions; c_noxfce; c_apps; c_user; c_system
command -v calamares || echo CALAMARES_REMOVED_PASS
test -f $H/AppImages/onlyoffice_desktopeditors.appimage && echo ONLYOFFICE_APPIMAGE_PASS || ls $H/AppImages
ls /usr/libexec/omaxian/keep-manual 2>/dev/null || echo KEEP_MANUAL_GONE_WITH_CALAMARES_SETTINGS
for p in fdisk switcheroo-control uuid-runtime media-player-info parted; do dpkg-query -W -f '${db:Status-Abbrev}' $p 2>/dev/null | grep -q ^ii && echo "KEPT_PASS $p" || echo "KEPT_FAIL $p"; done
flatpak list --system --app --columns=application 2>/dev/null
pgrep -af '(strata|folio)( |$)' | grep -v pgrep
echo R18_INSTALLED_DONE

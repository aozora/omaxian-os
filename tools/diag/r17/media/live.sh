#!/bin/bash
exec > >(tee /tmp/r17-live.log /dev/ttyS0) 2>&1
set +e; D=$(dirname "$0"); . $D/common.sh; U=omaxian; H=/home/omaxian
echo R17_LIVE_START; date -Iseconds
c_versions; c_noxfce; c_apps; c_user; c_system
/usr/libexec/omaxian/keep-manual --check && echo KEEP_MANUAL_CHECK_PASS || echo KEEP_MANUAL_CHECK_FAIL
grep -A3 'filemanager' /etc/calamares/settings.conf | head -8
echo R17_LIVE_DONE
if [ "${1:-}" = install ]; then
	sed -i 's/initialPartitioningChoice:.*/initialPartitioningChoice: erase/' /etc/calamares/modules/partition.conf
	pkill calamares; sleep 2
	DISPLAY=:0 XAUTHORITY=/home/omaxian/.Xauthority calamares >/tmp/calamares-relaunch.log 2>&1 &
fi

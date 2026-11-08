#!/bin/bash
exec > >(tee /tmp/round16-live-check.log /dev/ttyS0) 2>&1
echo ROUND16_LIVE_START
uname -r
strata --version
dpkg-query -W omaxian-session omaxian-base omaxian-strata sysvinit-core
pgrep -a quickshell
pgrep -a ydotoold
for b in disktree monologue omarchy-meeting-recorder signed; do
 p=/home/omaxian/.local/bin/$b
 test -x "$p" && echo "EXEC_PASS $b"
 ldd "$p" | grep 'not found' && echo "LDD_FAIL $b" || echo "LDD_PASS $b"
done
id omaxian
ls -l /dev/uinput
grep -R '127.0.0.1:8791' /etc/apt && echo PROXY_LEAK_FAIL || echo NO_BUILD_PROXY_PASS
flatpak list --app --columns=application,version
echo ROUND16_LIVE_DONE
if [ "${1:-}" = install ]; then
 sed -i 's/initialPartitioningChoice:.*/initialPartitioningChoice: erase/' /etc/calamares/modules/partition.conf
 pkill calamares
 DISPLAY=:0 XAUTHORITY=/home/omaxian/.Xauthority calamares >/tmp/calamares-relaunch.log 2>&1 &
fi

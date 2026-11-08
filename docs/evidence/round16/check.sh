#!/bin/bash
exec > >(tee /tmp/round16-installed-check.log /dev/ttyS0) 2>&1
set +e
echo ROUND16_INSTALLED_START
date -Iseconds
uname -r
dpkg-query -W omaxian-session omaxian-base omaxian-strata sysvinit-core eudev pipewire quickshell wireplumber
strata --version
pgrep -a quickshell
pgrep -a ydotoold
id tester
ls -l /dev/uinput
runuser -u tester -- test -w /dev/uinput && echo UINPUT_WRITABLE_PASS
for d in Desktop Documents Downloads Music Pictures Videos Templates Public; do test -d "/home/tester/$d" && echo "XDG_PASS $d" || echo "XDG_FAIL $d"; done
for b in disktree monologue omarchy-meeting-recorder signed; do
 p=/home/tester/.local/bin/$b
 test -x "$p" && echo "EXEC_PASS $b" || echo "EXEC_FAIL $b"
 ldd "$p" | grep 'not found' && echo "LDD_FAIL $b" || echo "LDD_PASS $b"
done
runuser -u tester -- /home/tester/.local/bin/disktree --help
runuser -u tester -- /home/tester/.local/bin/signed help
test -f /home/tester/AppImages/onlyoffice_desktopeditors.appimage && echo ONLYOFFICE_PASS
command -v calamares || echo CALAMARES_REMOVED_PASS
pgrep -a calamares || echo NO_INSTALLER_RUNNING_PASS
cat /etc/apt/sources.list.d/devuan.sources
grep -R -n -E '127.0.0.1:8791|Verify-Peer.*false|Verify-Host.*false|AllowUnauthenticated.*true' /etc/apt && echo APT_CONFIG_FAIL || echo APT_CONFIG_PASS
find /home/tester/.config -path '*/plugins/*' -maxdepth 8 -type f
echo ROUND16_INSTALLED_DONE

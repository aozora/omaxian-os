#!/bin/bash
# drive-install.sh <vm> <strata|folio> <hostname>: in a booted live VM run live.sh
# (checks + erase-default relaunch of Calamares), then drive Calamares by keyboard.
# Test-only password; it is a disposable VM with no network.
cd /workspace/omaxian-os; V=$1 FM=$2 HN=$3; D=build/round17
Q() { timeout 30 sudo python3 tools/qmon.py $D/$V.mon "$@" >/dev/null; }
shot() { bash tools/diag/r17/shot.sh $V "$1"; }
ser() { sudo cat $D/$V.serial.log | tr -d '\r'; }
Q sendkey meta_l-ret; sleep 5
Q type 'sudo mount /dev/sr1 /mnt; sudo bash /mnt/live.sh install\n'
for i in $(seq 60); do ser | grep -q R17_LIVE_DONE && break; sleep 5; done
ser | grep -q R17_LIVE_DONE || { echo LIVE_TIMEOUT; exit 1; }
echo LIVE_DONE; sleep 15; shot relaunched
for i in 1 2 3 4; do Q sendkey alt-n; sleep 3; done; shot users
Q type 'Tester'; Q sendkey tab; Q sendkey tab; Q sendkey ctrl-a; Q type "$HN"; Q sendkey tab
Q type 'Omx-test-2026'; Q sendkey tab; Q type 'Omx-test-2026'; sleep 1; shot users-filled
Q sendkey alt-n; sleep 3
[ $FM = folio ] && { Q sendkey tab; sleep 1; Q sendkey down; sleep 2; }
shot filemanager
Q sendkey alt-n; sleep 3; shot applications
Q sendkey alt-n; sleep 3; shot summary
Q sendkey alt-i; sleep 3; Q sendkey ret; sleep 10; shot installing
echo INSTALL_STARTED $(date +%T)

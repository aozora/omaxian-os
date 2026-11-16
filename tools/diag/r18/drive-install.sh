#!/bin/bash
# drive-install.sh <vm> <strata|folio> <hostname>: in a booted live VM run live.sh
# (checks + erase-default relaunch of Calamares), then drive Calamares by keyboard.
# Test-only password; it is a disposable VM with no network.
z() { sleep $(( $1 * ${SLOW:-1} )); }
cd /workspace/omaxian-os; V=$1 FM=$2 HN=$3; D=build/round18
Q() { timeout 30 sudo python3 tools/qmon.py $D/$V.mon "$@" >/dev/null; }
shot() { bash tools/diag/r18/shot.sh $V "$1"; }
ser() { sudo cat $D/$V.serial.log | tr -d '\r'; }
Q sendkey meta_l-ret; z 5
Q type 'sudo mount /dev/sr1 /mnt; sudo bash /mnt/live.sh install\n'
for i in $(seq $(( 60 * ${SLOW:-1} ))); do ser | grep -q R18_LIVE_DONE && break; z 5; done
ser | grep -q R18_LIVE_DONE || { echo LIVE_TIMEOUT; exit 1; }
echo LIVE_DONE; z 15; shot relaunched
for i in 1 2 3 4; do Q sendkey alt-n; z 3; done; shot users
Q type 'Tester'; Q sendkey tab; Q sendkey tab; Q sendkey ctrl-a; Q type "$HN"; Q sendkey tab
Q type 'Omx-test-2026'; Q sendkey tab; Q type 'Omx-test-2026'; z 1; shot users-filled
Q sendkey alt-n; z 3
[ $FM = folio ] && { Q sendkey tab; z 1; Q sendkey down; z 2; }
shot filemanager
Q sendkey alt-n; z 3; shot applications
Q sendkey alt-n; z 3; shot summary
Q sendkey alt-i; z 3; Q sendkey ret; z 10; shot installing
echo INSTALL_STARTED $(date +%T)

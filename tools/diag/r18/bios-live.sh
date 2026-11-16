#!/bin/bash
# bios-live.sh <vm> <base|full>: SeaBIOS live boot + live.sh checks (no install).
z() { sleep $(( $1 * ${SLOW:-1} )); }
cd /workspace/omaxian-os; V=$1 FL=$2; D=build/round18
Q() { timeout 30 sudo python3 tools/qmon.py $D/$V.mon "$@" >/dev/null; }
bash tools/diag/r18/vm.sh $V $FL bios cd || exit 1; z 120; bash tools/diag/r18/shot.sh $V live
Q sendkey meta_l-ret; z 5; Q type 'sudo mount /dev/sr1 /mnt; sudo bash /mnt/live.sh\n'
for i in $(seq $(( 60 * ${SLOW:-1} ))); do sudo cat $D/$V.serial.log | tr -d '\r' | grep -q R18_LIVE_DONE && break; z 5; done
bash tools/diag/r18/shot.sh $V done; sudo cat $D/$V.serial.log | tr -d '\r' | grep -q R18_LIVE_DONE && echo LIVE_DONE || echo LIVE_TIMEOUT
Q hmp quit; z 3; sudo rm -f $D/$V.qcow2; echo BIOS_END $(date +%T)

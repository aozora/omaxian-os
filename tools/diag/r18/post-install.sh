#!/bin/bash
# post-install.sh <vm> <base|full> <uefi|bios>: stop live VM, boot installed disk,
# log in as tester, press Super+Shift+F (file manager), run check.sh from R18TEST.
z() { sleep $(( $1 * ${SLOW:-1} )); }
cd /workspace/omaxian-os; V=$1 FL=$2 FW=${3:-uefi}; D=build/round18
Q() { timeout 30 sudo python3 tools/qmon.py $D/$V.mon "$@" >/dev/null; }
shot() { bash tools/diag/r18/shot.sh $V "$1"; }
ser() { sudo cat $D/$V.serial.log | tr -d '\r'; }
Q hmp quit; z 3; while pgrep -f "qemu-system.*$V.qcow2" >/dev/null; do z 2; done
sudo cp $D/$V.serial.log $D/$V.live.serial.log; sudo rm -f $D/$V.serial.log
bash tools/diag/r18/vm.sh $V $FL $FW disk; z 75; shot greeter
Q type 'Omx-test-2026\n'; z 60; shot desktop
Q sendkey meta_l-shift-f; z 8; shot superShiftF
Q sendkey meta_l-ret; z 5
Q type 'sudo mount /dev/sr0 /mnt; sudo bash /mnt/check.sh\n'; z 4; Q type 'Omx-test-2026\n'
for i in $(seq $(( 60 * ${SLOW:-1} ))); do ser | grep -q R18_INSTALLED_DONE && break; z 5; done
ser | grep -q R18_INSTALLED_DONE && echo CHECK_DONE || echo CHECK_TIMEOUT; shot check

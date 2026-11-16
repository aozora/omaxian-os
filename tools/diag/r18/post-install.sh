#!/bin/bash
# post-install.sh <vm> <base|full> <uefi|bios>: stop live VM, boot installed disk,
# log in as tester, press Super+Shift+F (file manager), run check.sh from R18TEST.
cd /workspace/omaxian-os; V=$1 FL=$2 FW=${3:-uefi}; D=build/round18
Q() { timeout 30 sudo python3 tools/qmon.py $D/$V.mon "$@" >/dev/null; }
shot() { bash tools/diag/r18/shot.sh $V "$1"; }
ser() { sudo cat $D/$V.serial.log | tr -d '\r'; }
Q hmp quit; sleep 3; while pgrep -f "qemu-system.*$V.qcow2" >/dev/null; do sleep 2; done
sudo cp $D/$V.serial.log $D/$V.live.serial.log; sudo rm -f $D/$V.serial.log
bash tools/diag/r18/vm.sh $V $FL $FW disk; sleep 75; shot greeter
Q type 'Omx-test-2026\n'; sleep 60; shot desktop
Q sendkey meta_l-shift-f; sleep 8; shot superShiftF
Q sendkey meta_l-ret; sleep 5
Q type 'sudo mount /dev/sr0 /mnt; sudo bash /mnt/check.sh\n'; sleep 4; Q type 'Omx-test-2026\n'
for i in $(seq 60); do ser | grep -q R18_INSTALLED_DONE && break; sleep 5; done
ser | grep -q R18_INSTALLED_DONE && echo CHECK_DONE || echo CHECK_TIMEOUT; shot check

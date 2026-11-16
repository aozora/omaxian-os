#!/bin/bash
# ACCEL=tcg QCPU=max (no KVM) and SLOW=<n> (scales every wait in the r18 scripts) for a box whose KVM is broken.
# vm.sh <name> <base|full> <bios|uefi> <cd|disk> [ram_mb]: one KVM test VM (root), no network,
# serial -> build/round18/<name>.serial.log, HMP monitor build/round18/<name>.mon,
# disk build/round18/<name>.qcow2 (40G sparse), test media (R18TEST) on the 2nd IDE bus.
cd /workspace/omaxian-os; N=$1 FL=$2 FWM=$3 BOOT=$4 RAM=${5:-3072}; D=build/round18
pgrep -f qemu-system-x86_64 >/dev/null && { echo "another VM is running; one at a time" >&2; exit 1; }
ISO=out/0.2.1/omaxian-$FL-0.2.1-space-cat-amd64.iso
[ -e $D/$N.qcow2 ] || qemu-img create -f qcow2 $D/$N.qcow2 40G >/dev/null
FW=(); if [ $FWM = uefi ]; then [ -e $D/vars-$N.fd ] || cp /usr/share/OVMF/OVMF_VARS_4M.fd $D/vars-$N.fd
 FW=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd -drive if=pflash,format=raw,file=$D/vars-$N.fd); fi
CD=(-drive file=$ISO,media=cdrom,if=none,id=cd0 -device ide-cd,drive=cd0,bus=ide.0,bootindex=1)
[ $BOOT = disk ] && CD=()
sudo rm -f $D/$N.mon
sudo qemu-system-x86_64 -machine q35,accel=${ACCEL:-kvm} -cpu ${QCPU:-host} -m $RAM -smp 2 -vga virtio -display none "${FW[@]}" \
 -drive file=$D/$N.qcow2,if=virtio,format=qcow2,cache=unsafe,aio=threads "${CD[@]}" \
 -drive file=$D/test-media.iso,media=cdrom,if=none,id=cd1 -device ide-cd,drive=cd1,bus=ide.1 \
 -device qemu-xhci -device usb-tablet -nic none -serial file:$D/$N.serial.log \
 -monitor unix:$D/$N.mon,server,nowait -daemonize -pidfile $D/$N.pid && date +%T

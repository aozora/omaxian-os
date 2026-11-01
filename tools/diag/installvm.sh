#!/bin/bash
# installvm.sh <vm> live|disk : FLAVOR=full|base ISO (default full) UEFI install VM, 40G virtio disk, no network
cd /workspace/omaxian-os; VM=$1; M=build/qemu-$VM.mon; rm -f $M
ISO=out/omaxian-${FLAVOR:-full}-0.1-trans-siberian-shaman-amd64.iso
[ -e build/$VM.qcow2 ] || qemu-img create -f qcow2 build/$VM.qcow2 40G >/dev/null
[ "$2" = disk ] && rm -f build/vars-$VM.fd; [ -e build/vars-$VM.fd ] || cp /usr/share/OVMF/OVMF_VARS_4M.fd build/vars-$VM.fd
B=(-cdrom $ISO -boot d); [ "$2" = disk ] && B=()
qemu-system-x86_64 -machine q35 -m 4096 -smp 4 ${CPU:+-cpu $CPU} -vga virtio -display none \
 -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd -drive if=pflash,format=raw,file=build/vars-$VM.fd \
 -drive file=build/$VM.qcow2,if=virtio,format=qcow2 -monitor unix:$M,server,nowait -nic ${NIC:-none} -accel tcg,thread=multi \
 "${B[@]}" -daemonize -pidfile build/qemu-$VM.pid && date +%T
